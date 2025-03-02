#!/bin/bash

# complete-prometheus-setup.sh
# Comprehensive script to set up Prometheus on an EKS cluster with public access
# This script installs Prometheus with alertmanager persistence disabled to avoid PVC issues

set -e # Exit immediately if a command exits with a non-zero status

# -----------------
# Color definitions
# -----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------
# Helper functions
# -----------------
print_section() {
  echo -e "\n${BLUE}==== $1 ====${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

check_command() {
  if ! command -v $1 &>/dev/null; then
    print_error "$1 could not be found. Please make sure it's installed."
    exit 1
  fi
}

# -----------------
# Variables (can be customized)
# -----------------
PROMETHEUS_NAMESPACE="prometheus"
STORAGE_CLASS="ebs-sc" # Using the storage class created in the EBS CSI driver setup
CLUSTER_NAME="eks-mundos-e"
REGION="us-east-1"

# -----------------
# Prerequisite check
# -----------------
print_section "Checking prerequisites"

check_command "kubectl"
check_command "helm"

# Validate kubectl is connected to the cluster
echo "Validating Kubernetes cluster connection..."
if ! kubectl get nodes >/dev/null 2>&1; then
  print_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."

  # Try to update kubeconfig
  echo "Attempting to update kubeconfig..."
  if ! aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}; then
    print_error "Failed to update kubeconfig. Please verify the cluster name and region."
    exit 1
  fi

  # Check again
  if ! kubectl get nodes >/dev/null 2>&1; then
    print_error "Still cannot connect to the cluster. Please check your AWS credentials and permissions."
    exit 1
  fi
fi
print_success "Connected to Kubernetes cluster"

# Check if storage class exists
echo "Checking if storage class '${STORAGE_CLASS}' exists..."
if ! kubectl get sc ${STORAGE_CLASS} >/dev/null 2>&1; then
  print_warning "Storage class '${STORAGE_CLASS}' not found. Checking for other storage classes..."

  # List available storage classes
  AVAILABLE_SC=$(kubectl get sc -o jsonpath='{.items[*].metadata.name}')

  if [ -z "$AVAILABLE_SC" ]; then
    print_error "No storage classes found. Please set up a storage class first (e.g., using the EBS CSI driver)."
    exit 1
  else
    print_warning "Available storage classes: $AVAILABLE_SC"
    print_warning "Using 'gp2' as a fallback storage class."
    STORAGE_CLASS="gp2"
  fi
else
  print_success "Storage class '${STORAGE_CLASS}' found"
fi

# -----------------
# Check if Prometheus is already installed
# -----------------
print_section "Checking for existing Prometheus installation"

if kubectl get namespace ${PROMETHEUS_NAMESPACE} >/dev/null 2>&1; then
  if helm list -n ${PROMETHEUS_NAMESPACE} | grep prometheus >/dev/null 2>&1; then
    print_warning "Prometheus is already installed in namespace '${PROMETHEUS_NAMESPACE}'"

    read -p "Do you want to remove the existing installation and start fresh? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Uninstalling Prometheus..."
      helm uninstall prometheus -n ${PROMETHEUS_NAMESPACE}

      # Delete all PVCs to ensure clean state
      echo "Deleting all persistent volume claims..."
      kubectl delete pvc --all -n ${PROMETHEUS_NAMESPACE}

      # Wait a moment for resources to be cleaned up
      echo "Waiting for resources to be cleaned up..."
      sleep 10
    else
      print_warning "Keeping existing installation"

      # Skip to exposing Prometheus publicly
      SKIP_INSTALL=true
    fi
  fi
else
  echo "Creating namespace '${PROMETHEUS_NAMESPACE}'..."
  kubectl create namespace ${PROMETHEUS_NAMESPACE}
fi

# -----------------
# Add Helm repository
# -----------------
if [ "${SKIP_INSTALL}" != "true" ]; then
  print_section "Setting up Helm repository"

  echo "Adding Prometheus Helm repository..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo update
  print_success "Helm repository updated"

  # -----------------
  # Create values file
  # -----------------
  print_section "Creating Prometheus configuration"

  # Create temporary values file
  cat >prometheus-values.yaml <<EOF
alertmanager:
  persistentVolume:
    enabled: false  # Disable alertmanager persistence to avoid PVC issues
  resources:
    limits:
      cpu: 100m
      memory: 256Mi
    requests:
      cpu: 50m
      memory: 128Mi

server:
  persistentVolume:
    enabled: true
    storageClass: "${STORAGE_CLASS}"
    size: 10Gi
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 200m
      memory: 256Mi

pushgateway:
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

nodeExporter:
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi

kubeStateMetrics:
  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 50m
      memory: 64Mi
EOF

  print_success "Prometheus configuration created"

  # -----------------
  # Install Prometheus
  # -----------------
  print_section "Installing Prometheus"

  echo "Installing Prometheus..."
  helm install prometheus prometheus-community/prometheus \
    --namespace ${PROMETHEUS_NAMESPACE} \
    --values prometheus-values.yaml

  print_success "Prometheus installation complete"

  # -----------------
  # Wait for pods to be ready
  # -----------------
  print_section "Waiting for Prometheus server pod to start"

  echo "This may take a few minutes..."
  ATTEMPTS=0
  MAX_ATTEMPTS=20

  # Wait for server pod to be running
  while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))

    # Get the server pod status
    SERVER_POD=$(kubectl get pods -n ${PROMETHEUS_NAMESPACE} -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server" -o name 2>/dev/null || echo "")

    if [ -n "$SERVER_POD" ]; then
      SERVER_READY=$(kubectl get $SERVER_POD -n ${PROMETHEUS_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

      if [ "$SERVER_READY" == "Running" ]; then
        print_success "Prometheus server is running"
        break
      fi
    fi

    if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
      print_warning "Timed out waiting for Prometheus server to start"

      # Check pod status
      echo "Current pod status:"
      kubectl get pods -n ${PROMETHEUS_NAMESPACE}

      read -p "Do you want to continue anyway? (y/n): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Setup aborted"
        exit 1
      fi
      break
    fi

    echo -n "."
    sleep 10
  done

  echo ""

  # Display pod status
  echo "Prometheus pod status:"
  kubectl get pods -n ${PROMETHEUS_NAMESPACE}
fi

# -----------------
# Create external access
# -----------------
print_section "Setting up public access for Prometheus"

# Check if external service already exists
if kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external >/dev/null 2>&1; then
  print_warning "External service 'prometheus-external' already exists"

  read -p "Do you want to replace it? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting existing service..."
    kubectl delete svc -n ${PROMETHEUS_NAMESPACE} prometheus-external
  else
    print_warning "Using existing service"

    # Get the LoadBalancer URL
    ELB=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

    if [ -n "$ELB" ]; then
      print_success "Prometheus is already accessible at: http://${ELB}"
    else
      print_warning "LoadBalancer URL not available yet. Check with: kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external"
    fi

    exit 0
  fi
fi

# -----------------
# Create the LoadBalancer service
# -----------------
echo "Creating LoadBalancer service for Prometheus..."

# Create a service manifest file
cat >prometheus-external-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus-external
  namespace: ${PROMETHEUS_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "classic"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 9090
    protocol: TCP
    name: http
  selector:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/component: server
EOF

# Apply the service manifest
kubectl apply -f prometheus-external-service.yaml

print_success "LoadBalancer service created"

# -----------------
# Wait for LoadBalancer to be provisioned
# -----------------
print_section "Waiting for LoadBalancer to be provisioned"

echo "This may take a few minutes..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ATTEMPTS=$((ATTEMPTS + 1))

  # Check for endpoints first
  ENDPOINTS=$(kubectl get endpoints -n ${PROMETHEUS_NAMESPACE} prometheus-external -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)

  if [ -z "$ENDPOINTS" ] && [ $ATTEMPTS -eq 10 ]; then
    print_warning "Service has no endpoints. Trying alternative selectors..."

    # Try alternative selector combinations
    cat >prometheus-external-service-alt.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus-external
  namespace: ${PROMETHEUS_NAMESPACE}
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "classic"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 9090
    protocol: TCP
    name: http
  selector:
    app: prometheus
    component: server
EOF

    kubectl delete svc -n ${PROMETHEUS_NAMESPACE} prometheus-external
    kubectl apply -f prometheus-external-service-alt.yaml
  fi

  # Try to get the LoadBalancer address
  ELB=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

  if [ -n "$ELB" ] && [ "$ELB" != "<pending>" ]; then
    # Check endpoints again
    ENDPOINTS=$(kubectl get endpoints -n ${PROMETHEUS_NAMESPACE} prometheus-external -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)

    if [ -n "$ENDPOINTS" ]; then
      print_success "LoadBalancer provisioned with working endpoints"
      break
    fi

    # If still no endpoints, try one more approach as last resort
    if [ $ATTEMPTS -eq 20 ] && [ -z "$ENDPOINTS" ]; then
      print_warning "Still no endpoints. Creating direct endpoint connection..."

      SERVER_IP=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-server -o jsonpath='{.spec.clusterIP}')

      kubectl delete svc -n ${PROMETHEUS_NAMESPACE} prometheus-external

      # Create service and endpoints
      cat >prometheus-external-direct.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: prometheus-external
  namespace: ${PROMETHEUS_NAMESPACE}
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: prometheus-external
  namespace: ${PROMETHEUS_NAMESPACE}
subsets:
  - addresses:
      - ip: ${SERVER_IP}
    ports:
      - port: 80
EOF

      kubectl apply -f prometheus-external-direct.yaml
    fi
  fi

  if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    print_warning "Timed out waiting for LoadBalancer"
    break
  fi

  echo -n "."
  sleep 10
done

echo ""

# Display the final service and endpoints
kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external
kubectl get endpoints -n ${PROMETHEUS_NAMESPACE} prometheus-external

# -----------------
# Access information
# -----------------
print_section "Access Information"

ELB=$(kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -n "$ELB" ]; then
  print_success "Prometheus is now accessible at: http://${ELB}"

  # Verify basic connectivity
  echo "Verifying Prometheus accessibility (this may take a minute)..."
  if curl -s --max-time 30 "http://${ELB}/graph" | grep -q "Prometheus"; then
    print_success "Prometheus is responding correctly"
  else
    print_warning "Could not verify Prometheus response. It may need more time to initialize."
    print_warning "Try accessing http://${ELB} in your browser after a few minutes."
  fi
else
  print_warning "LoadBalancer address not yet available"
  echo "Check the status with: kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-external"
fi

# -----------------
# Port forwarding option
# -----------------
print_section "Alternative Access Options"

echo "If the LoadBalancer approach doesn't work, you can use port forwarding:"
echo "kubectl port-forward -n ${PROMETHEUS_NAMESPACE} svc/prometheus-server 9090:80 --address 0.0.0.0"
echo "Then access Prometheus at: http://YOUR_EC2_PUBLIC_IP:9090"

# -----------------
# Summary and next steps
# -----------------
print_section "Summary and Next Steps"

echo "Prometheus has been set up on your EKS cluster with the following components:"

echo "1. Namespace: ${PROMETHEUS_NAMESPACE}"
echo "2. Storage Class: ${STORAGE_CLASS} (for server component)"
echo "3. Alertmanager: Running without persistence"
echo "4. LoadBalancer service: prometheus-external"
echo ""

if [ -n "$ELB" ]; then
  echo "Access Prometheus at: http://${ELB}"
else
  echo "Access Prometheus via port forwarding or check the LoadBalancer status"
fi

echo ""
echo "Next steps:"
echo "1. Set up Grafana to visualize Prometheus metrics"
echo "2. Import Kubernetes dashboards for monitoring (IDs: 3119, 6417)"
echo "3. Configure alerts if needed"

print_success "Prometheus setup complete!"

# Clean up temporary files
rm -f prometheus-values.yaml prometheus-external-service.yaml prometheus-external-service-alt.yaml prometheus-external-direct.yaml 2>/dev/null
