#!/bin/bash

# ec2-cleanup.sh
# Script to clean up Kubernetes resources and EKS cluster
# Run this script FROM the EC2 workstation

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

prompt_continue() {
  local message=$1
  local default_yes=${2:-true}

  if [ "$default_yes" = true ]; then
    read -p "$message [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
      return 1
    fi
  else
    read -p "$message [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi

  return 0
}

# -----------------
# Configuration variables
# -----------------
# EKS cluster info
CLUSTER_NAME="eks-mundos-e"
REGION="us-east-1"

# -----------------
# Prerequisites check
# -----------------
print_section "Checking Prerequisites"

# Check for required commands
for cmd in kubectl helm aws eksctl; do
  if ! command -v $cmd &>/dev/null; then
    print_error "$cmd could not be found. Please make sure it's installed."
    exit 1
  fi
done

print_success "All required tools are available"

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
  print_error "AWS credentials not configured or invalid"
  if prompt_continue "Do you want to configure AWS credentials now?" false; then
    aws configure
  else
    print_error "Cannot continue without valid AWS credentials"
    exit 1
  fi
else
  print_success "AWS credentials verified"
fi

# Check EKS cluster connection
echo "Checking connection to EKS cluster..."
if ! kubectl get nodes &>/dev/null; then
  print_warning "Cannot connect to EKS cluster. Attempting to update kubeconfig..."

  if aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}; then
    print_success "Connected to EKS cluster"
  else
    print_error "Failed to connect to EKS cluster. Please verify the cluster exists and you have the correct permissions."

    # Check if cluster exists
    if ! aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} &>/dev/null; then
      print_warning "Cluster '${CLUSTER_NAME}' does not exist or you don't have permission to access it"

      if prompt_continue "Skip to EKS cluster cleanup?"; then
        # Set flag to skip kubernetes resource cleanup
        SKIP_K8S_CLEANUP=true
      else
        print_error "Cleanup aborted"
        exit 1
      fi
    else
      print_error "Cluster exists but kubectl cannot connect to it"
      exit 1
    fi
  fi
else
  print_success "Connected to EKS cluster"
fi

# -----------------
# Step 1: Clean up Kubernetes resources
# -----------------
if [ "$SKIP_K8S_CLEANUP" != true ]; then
  print_section "Step 1: Cleaning up Kubernetes resources"

  # Clean up Grafana
  echo "Cleaning up Grafana..."
  if kubectl get namespace grafana &>/dev/null; then
    echo "Uninstalling Grafana Helm release..."
    helm uninstall grafana --namespace grafana || print_warning "Failed to uninstall Grafana Helm release"

    echo "Deleting Grafana PVCs..."
    kubectl delete pvc --all --namespace grafana || print_warning "Failed to delete Grafana PVCs"

    echo "Deleting Grafana namespace..."
    kubectl delete namespace grafana || print_warning "Failed to delete Grafana namespace"

    rm -rf ${HOME}/environment/grafana 2>/dev/null || print_warning "Failed to delete Grafana config directory"
    print_success "Grafana resources cleaned up"
  else
    print_warning "Grafana namespace not found, skipping"
  fi

  # Clean up Prometheus
  echo "Cleaning up Prometheus..."
  if kubectl get namespace prometheus &>/dev/null; then
    echo "Uninstalling Prometheus Helm release..."
    helm uninstall prometheus --namespace prometheus || print_warning "Failed to uninstall Prometheus Helm release"

    echo "Deleting Prometheus PVCs..."
    kubectl delete pvc --all --namespace prometheus || print_warning "Failed to delete Prometheus PVCs"

    echo "Deleting Prometheus namespace..."
    kubectl delete namespace prometheus || print_warning "Failed to delete Prometheus namespace"
    print_success "Prometheus resources cleaned up"
  else
    print_warning "Prometheus namespace not found, skipping"
  fi

  # Clean up any other test resources
  echo "Cleaning up any NGINX test deployments..."
  kubectl delete deployment nginx &>/dev/null || true
  kubectl delete service nginx &>/dev/null || true
  print_success "NGINX test resources cleaned up"
else
  print_warning "Skipping Kubernetes resource cleanup as requested"
fi

# -----------------
# Step 2: Delete EKS cluster
# -----------------
print_section "Step 2: Deleting EKS cluster"

echo "Checking if EKS cluster exists..."
if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} &>/dev/null; then
  echo "EKS cluster '${CLUSTER_NAME}' exists"

  if prompt_continue "Are you sure you want to delete the EKS cluster? This cannot be undone"; then
    echo "Deleting EKS cluster. This may take 10-15 minutes..."

    # Delete the cluster using eksctl
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${REGION}

    if [ $? -eq 0 ]; then
      print_success "EKS cluster deleted successfully"
    else
      print_error "Failed to delete EKS cluster"

      # Offer alternate deletion method
      if prompt_continue "Do you want to attempt deletion with AWS CLI instead?" false; then
        echo "Attempting deletion with AWS CLI..."

        # Get all associated nodegroups
        NODEGROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --region ${REGION} --query 'nodegroups[*]' --output text)

        # Delete each nodegroup
        for ng in $NODEGROUPS; do
          echo "Deleting nodegroup $ng..."
          aws eks delete-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng --region ${REGION}

          # Wait for nodegroup to be deleted
          echo "Waiting for nodegroup deletion to complete..."
          aws eks wait nodegroup-deleted --cluster-name ${CLUSTER_NAME} --nodegroup-name $ng --region ${REGION}
        done

        # Delete the cluster
        echo "Deleting EKS cluster..."
        aws eks delete-cluster --name ${CLUSTER_NAME} --region ${REGION}

        # Wait for cluster to be deleted
        echo "Waiting for cluster deletion to complete..."
        aws eks wait cluster-deleted --name ${CLUSTER_NAME} --region ${REGION}

        print_success "EKS cluster deleted using AWS CLI"
      else
        print_warning "EKS cluster deletion failed but continuing with cleanup"
      fi
    fi
  else
    print_warning "EKS cluster deletion skipped"
  fi
else
  print_warning "EKS cluster '${CLUSTER_NAME}' not found, skipping deletion"
fi

# -----------------
# Final summary
# -----------------
print_section "Cleanup Summary"

echo "The following resources have been cleaned up:"
[ "$SKIP_K8S_CLEANUP" != true ] && echo "✓ Kubernetes resources (Grafana, Prometheus, NGINX)"
echo "✓ EKS cluster: ${CLUSTER_NAME} (or attempt was made to delete it)"

print_success "EC2 workstation cleanup complete!"
echo "Now you can safely terminate this EC2 instance using the local cleanup script."
echo -e "\n${YELLOW}IMPORTANT: After running this script, save any important data from this EC2 instance before exiting.${NC}"
echo -e "${YELLOW}The next step is to run the local-cleanup.sh script from your local machine to remove the Terraform infrastructure.${NC}"
