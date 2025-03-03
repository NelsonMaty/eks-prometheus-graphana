#!/bin/bash

# grafana-setup.sh
# Script to set up Grafana on an EKS cluster with Prometheus data source
# and import Kubernetes dashboards

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
GRAFANA_NAMESPACE="grafana"
PROMETHEUS_NAMESPACE="prometheus"
STORAGE_CLASS="ebs-sc" # Using the storage class created in the EBS CSI driver setup
CLUSTER_NAME="eks-mundos-e"
REGION="us-east-1"
GRAFANA_ADMIN_PASSWORD="EKS!sAWSome" # Default password as mentioned in your documentation

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

# Check if Prometheus is running
echo "Checking if Prometheus is deployed in namespace '${PROMETHEUS_NAMESPACE}'..."
if ! kubectl get namespace ${PROMETHEUS_NAMESPACE} >/dev/null 2>&1; then
  print_error "Prometheus namespace '${PROMETHEUS_NAMESPACE}' not found. Please deploy Prometheus first."
  exit 1
fi

if ! kubectl get svc -n ${PROMETHEUS_NAMESPACE} prometheus-server >/dev/null 2>&1; then
  print_error "Prometheus server service not found. Please make sure Prometheus is properly deployed."
  exit 1
fi
print_success "Prometheus is deployed and running"

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
# Check if Grafana is already installed
# -----------------
print_section "Checking for existing Grafana installation"

if kubectl get namespace ${GRAFANA_NAMESPACE} >/dev/null 2>&1; then
  if helm list -n ${GRAFANA_NAMESPACE} | grep grafana >/dev/null 2>&1; then
    print_warning "Grafana is already installed in namespace '${GRAFANA_NAMESPACE}'"

    read -p "Do you want to remove the existing installation and start fresh? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Uninstalling Grafana..."
      helm uninstall grafana -n ${GRAFANA_NAMESPACE}

      # Delete all PVCs to ensure clean state
      echo "Deleting all persistent volume claims..."
      kubectl delete pvc --all -n ${GRAFANA_NAMESPACE}

      # Wait a moment for resources to be cleaned up
      echo "Waiting for resources to be cleaned up..."
      sleep 10
    else
      print_warning "Keeping existing installation"

      # Skip to exposing Grafana publicly
      SKIP_INSTALL=true
    fi
  fi
else
  echo "Creating namespace '${GRAFANA_NAMESPACE}'..."
  kubectl create namespace ${GRAFANA_NAMESPACE}
fi

# -----------------
# Add Helm repository
# -----------------
if [ "${SKIP_INSTALL}" != "true" ]; then
  print_section "Setting up Helm repository"

  echo "Adding Grafana Helm repository..."
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  print_success "Helm repository updated"

  # -----------------
  # Create values file with Prometheus data source
  # -----------------
  print_section "Creating Grafana configuration"

  # Get Prometheus server URL (cluster internal URL)
  PROMETHEUS_URL="http://prometheus-server.${PROMETHEUS_NAMESPACE}.svc.cluster.local"
  echo "Prometheus URL for data source: ${PROMETHEUS_URL}"

  # Create values file with Grafana configuration
  mkdir -p ${HOME}/environment/grafana
  cat >${HOME}/environment/grafana/grafana.yaml <<EOF
persistence:
  enabled: true
  storageClassName: "${STORAGE_CLASS}"
  size: 10Gi

adminPassword: "${GRAFANA_ADMIN_PASSWORD}"

service:
  type: LoadBalancer

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: ${PROMETHEUS_URL}
      access: proxy
      isDefault: true

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'kubernetes'
      orgId: 1
      folder: 'Kubernetes'
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/kubernetes

dashboards:
  kubernetes:
    # Kubernetes Cluster Monitoring dashboard
    k8s-cluster-monitoring:
      gnetId: 3119
      revision: 2
      datasource: Prometheus
    
    # Kubernetes Pod Monitoring dashboard
    k8s-pod-monitoring:
      gnetId: 6417
      revision: 1
      datasource: Prometheus

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi
EOF

  print_success "Grafana configuration created"

  # -----------------
  # Install Grafana
  # -----------------
  print_section "Installing Grafana"

  echo "Installing Grafana..."
  helm install grafana grafana/grafana \
    --namespace ${GRAFANA_NAMESPACE} \
    --values ${HOME}/environment/grafana/grafana.yaml

  print_success "Grafana installation complete"

  # -----------------
  # Wait for pods to be ready
  # -----------------
  print_section "Waiting for Grafana pod to start"

  echo "This may take a few minutes..."
  ATTEMPTS=0
  MAX_ATTEMPTS=20

  # Wait for Grafana pod to be running
  while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))

    # Get the Grafana pod status
    GRAFANA_POD=$(kubectl get pods -n ${GRAFANA_NAMESPACE} -l "app.kubernetes.io/name=grafana" -o name 2>/dev/null || echo "")

    if [ -n "$GRAFANA_POD" ]; then
      GRAFANA_READY=$(kubectl get $GRAFANA_POD -n ${GRAFANA_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

      if [ "$GRAFANA_READY" == "Running" ]; then
        print_success "Grafana pod is running"
        break
      fi
    fi

    if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
      print_warning "Timed out waiting for Grafana pod to start"

      # Check pod status
      echo "Current pod status:"
      kubectl get pods -n ${GRAFANA_NAMESPACE}

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
  echo "Grafana pod status:"
  kubectl get pods -n ${GRAFANA_NAMESPACE}
fi

# -----------------
# Wait for LoadBalancer to be provisioned
# -----------------
print_section "Waiting for LoadBalancer to be provisioned"

echo "This may take a few minutes..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  ATTEMPTS=$((ATTEMPTS + 1))

  # Try to get the LoadBalancer address
  ELB=$(kubectl get svc -n ${GRAFANA_NAMESPACE} grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

  if [ -n "$ELB" ] && [ "$ELB" != "<pending>" ]; then
    print_success "LoadBalancer provisioned"
    break
  fi

  if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
    print_warning "Timed out waiting for LoadBalancer"
    break
  fi

  echo -n "."
  sleep 10
done

echo ""

# Display the final service
kubectl get svc -n ${GRAFANA_NAMESPACE} grafana

# -----------------
# Get Grafana admin password
# -----------------
print_section "Grafana Access Information"

# Get the admin password if it's stored in a secret
if [ "${SKIP_INSTALL}" != "true" ]; then
  echo "Admin password: ${GRAFANA_ADMIN_PASSWORD} (as configured)"
else
  echo "Retrieving admin password from secret..."
  ADMIN_PASSWORD=$(kubectl get secret --namespace ${GRAFANA_NAMESPACE} grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
  echo "Admin password: ${ADMIN_PASSWORD}"
fi

# -----------------
# Access information
# -----------------
ELB=$(kubectl get svc -n ${GRAFANA_NAMESPACE} grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -n "$ELB" ]; then
  print_success "Grafana is now accessible at: http://${ELB}"
  echo "Login with:"
  echo "  Username: admin"
  echo "  Password: ${GRAFANA_ADMIN_PASSWORD}"

  # Verify basic connectivity
  echo "Verifying Grafana accessibility (this may take a minute)..."
  if curl -s --max-time 30 "http://${ELB}/login" | grep -q "Grafana"; then
    print_success "Grafana is responding correctly"
  else
    print_warning "Could not verify Grafana response. It may need more time to initialize."
    print_warning "Try accessing http://${ELB} in your browser after a few minutes."
  fi
else
  print_warning "LoadBalancer address not yet available"
  echo "Check the status with: kubectl get svc -n ${GRAFANA_NAMESPACE} grafana"
fi

# -----------------
# Port forwarding option
# -----------------
print_section "Alternative Access Options"

echo "If the LoadBalancer approach doesn't work, you can use port forwarding:"
echo "kubectl port-forward -n ${GRAFANA_NAMESPACE} svc/grafana 3000:80 --address 0.0.0.0"
echo "Then access Grafana at: http://YOUR_EC2_PUBLIC_IP:3000"

# -----------------
# Dashboards verification
# -----------------
print_section "Dashboards Verification"

echo "The following dashboards should be automatically imported:"
echo "1. Kubernetes Cluster Monitoring (ID: 3119)"
echo "2. Kubernetes Pod Monitoring (ID: 6417)"
echo ""
echo "If the dashboards are not automatically imported, you can import them manually:"
echo "1. Login to Grafana"
echo "2. Click on the '+' icon on the left sidebar and select 'Import'"
echo "3. Enter the dashboard ID (3119 or 6417)"
echo "4. Select 'Prometheus' as the data source"
echo "5. Click 'Import'"

# -----------------
# Summary and next steps
# -----------------
print_section "Summary and Next Steps"

echo "Grafana has been set up on your EKS cluster with the following configuration:"
echo "1. Namespace: ${GRAFANA_NAMESPACE}"
echo "2. Storage Class: ${STORAGE_CLASS} (for persistent storage)"
echo "3. Prometheus data source: ${PROMETHEUS_URL}"
echo "4. Pre-configured dashboards: Kubernetes Cluster (#3119) and Pod Monitoring (#6417)"
echo ""

if [ -n "$ELB" ]; then
  echo "Access Grafana at: http://${ELB}"
  echo "Username: admin"
  echo "Password: ${GRAFANA_ADMIN_PASSWORD}"
else
  echo "Access Grafana via port forwarding or check the LoadBalancer status"
fi

echo ""
echo "Once logged in:"
echo "1. Verify the Prometheus data source is working correctly (Configuration > Data Sources)"
echo "2. Browse to the imported dashboards (Dashboards > Browse)"
echo "3. Create additional dashboards or alerts as needed"

print_success "Grafana setup complete!"
