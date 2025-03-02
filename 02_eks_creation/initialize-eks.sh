#!/bin/bash

# initialize-eks.sh
# Script to initialize an EKS cluster and deploy NGINX
# Run this script from your EC2 workstation

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
CLUSTER_NAME="eks-mundos-e"
REGION="us-east-1"
NODE_TYPE="t3.small"
NODE_COUNT=3
ZONES="us-east-1a,us-east-1b,us-east-1c"
SSH_KEY_NAME="pin"

# -----------------
# Prerequisite check
# -----------------
print_section "Checking prerequisites"

check_command "aws"
check_command "eksctl"
check_command "kubectl"
check_command "jq"

# Validate AWS CLI is configured
echo "Validating AWS configuration..."
aws sts get-caller-identity >/dev/null 2>&1 || {
  print_error "AWS CLI is not configured correctly. Run 'aws configure'."
  exit 1
}
print_success "AWS CLI is configured correctly"

# Check if SSH key exists
if [ ! -f ~/.ssh/${SSH_KEY_NAME}.pub ]; then
  print_warning "SSH key ${SSH_KEY_NAME}.pub not found in ~/.ssh/"

  read -p "Do you want to generate a new SSH key? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/${SSH_KEY_NAME} -N ""
    print_success "SSH key generated at ~/.ssh/${SSH_KEY_NAME}"
  else
    print_error "SSH key is required. Please provide a valid key."
    exit 1
  fi
fi

# -----------------
# Cluster creation
# -----------------
print_section "Creating EKS cluster ${CLUSTER_NAME}"

# Check if cluster already exists
if eksctl get cluster --name ${CLUSTER_NAME} --region ${REGION} 2>/dev/null; then
  print_warning "Cluster ${CLUSTER_NAME} already exists"

  read -p "Do you want to proceed with the existing cluster? (y/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Operation cancelled"
    exit 1
  fi
else
  echo "Creating new EKS cluster. This may take 15-20 minutes..."

  eksctl create cluster \
    --name ${CLUSTER_NAME} \
    --region ${REGION} \
    --node-type ${NODE_TYPE} \
    --nodes ${NODE_COUNT} \
    --with-oidc \
    --ssh-access \
    --ssh-public-key ${SSH_KEY_NAME} \
    --managed \
    --full-ecr-access \
    --zones ${ZONES}

  print_success "EKS cluster ${CLUSTER_NAME} created successfully"
fi

# -----------------
# Validate cluster
# -----------------
print_section "Validating cluster connection"

# Update kubeconfig
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
print_success "Updated kubeconfig"

# Check nodes
echo "Checking nodes..."
kubectl get nodes -o wide
if [ $? -ne 0 ]; then
  print_error "Failed to get nodes. There may be an issue with the cluster."
  exit 1
fi

# Check core pods
echo "Checking Kubernetes system pods..."
kubectl get pods -n kube-system
print_success "Cluster validation complete"

# -----------------
# Deploy Nginx
# -----------------
print_section "Deploying NGINX"

# Check if NGINX deployment already exists
if kubectl get deployment nginx &>/dev/null; then
  print_warning "NGINX deployment already exists"
else
  # Create NGINX deployment
  kubectl create deployment nginx --image=nginx
  print_success "NGINX deployment created"
fi

# Check if NGINX service already exists
if kubectl get service nginx &>/dev/null; then
  print_warning "NGINX service already exists"
else
  # Expose NGINX deployment
  kubectl expose deployment nginx --port=80 --type=LoadBalancer
  print_success "NGINX service created (LoadBalancer)"
fi

# -----------------
# Wait for LoadBalancer
# -----------------
print_section "Waiting for LoadBalancer to be provisioned"

echo "This may take a few minutes..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while true; do
  ATTEMPTS=$((ATTEMPTS + 1))

  # Get the external IP/hostname
  EXTERNAL_IP=$(kubectl get service nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
    break
  fi

  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    print_warning "Timed out waiting for LoadBalancer. You can check its status later with 'kubectl get services'"
    break
  fi

  echo -n "."
  sleep 10
done

echo ""

if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
  print_success "LoadBalancer provisioned"
  echo -e "\n${GREEN}NGINX is now accessible at:${NC} http://${EXTERNAL_IP}"

  # Check if the service is responding
  print_section "Testing NGINX accessibility"
  echo "Sending HTTP request to NGINX LoadBalancer..."

  if curl -s --max-time 10 "http://${EXTERNAL_IP}" | grep -q "Welcome to nginx"; then
    print_success "NGINX is responding correctly"
  else
    print_warning "Unable to connect to NGINX. The LoadBalancer may still be configuring."
    print_warning "Try accessing http://${EXTERNAL_IP} in your browser after a few minutes."
  fi
fi

# -----------------
# Summary
# -----------------
print_section "Deployment Summary"
echo "EKS cluster name: ${CLUSTER_NAME}"
echo "Kubernetes version: $(kubectl version --short | grep Server)"
echo "Node count: $(kubectl get nodes | grep -v NAME | wc -l)"
echo "NGINX deployment: $(kubectl get deployment nginx -o jsonpath='{.status.readyReplicas}')/$(kubectl get deployment nginx -o jsonpath='{.spec.replicas}') replicas ready"
echo "NGINX service type: LoadBalancer"

if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ]; then
  echo "NGINX URL: http://${EXTERNAL_IP}"
else
  echo "NGINX URL: Pending (check with 'kubectl get services')"
fi

print_section "Next Steps"
echo "1. Access NGINX at the URL shown above"
echo "2. Install monitoring tools (Prometheus and Grafana)"
echo "3. Clean up when done: eksctl delete cluster --name ${CLUSTER_NAME} --region ${REGION}"

print_success "Setup complete!"
