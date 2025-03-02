#!/bin/bash

# Script to set up the AWS EBS CSI Driver on an EKS cluster
# This script uses the AWS EKS add-on method (recommended approach)

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
IAM_ROLE_NAME="AmazonEKS_EBS_CSI_DriverRole"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

# -----------------
# Prerequisite check
# -----------------
print_section "Checking prerequisites"

check_command "aws"
check_command "kubectl"
check_command "jq"

# Validate AWS CLI is configured
echo "Validating AWS configuration..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  print_error "AWS CLI is not configured correctly. Run 'aws configure'."
  exit 1
fi
print_success "AWS CLI is configured correctly"

# Validate EKS cluster
echo "Validating EKS cluster connection..."
if ! kubectl get nodes >/dev/null 2>&1; then
  print_error "Cannot connect to EKS cluster. Check your kubeconfig."

  # Try to update kubeconfig
  echo "Attempting to update kubeconfig..."
  if ! aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}; then
    print_error "Failed to update kubeconfig. Please verify the cluster name and region."
    exit 1
  fi

  # Check again
  if ! kubectl get nodes >/dev/null 2>&1; then
    print_error "Still cannot connect to EKS cluster. Please check your AWS credentials and permissions."
    exit 1
  fi
fi
print_success "Connected to EKS cluster '${CLUSTER_NAME}'"

# -----------------
# Check if add-on already exists
# -----------------
print_section "Checking existing EBS CSI driver installation"

if aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --region ${REGION} >/dev/null 2>&1; then
  print_warning "EBS CSI driver add-on already installed"

  # Check if it's working properly
  if kubectl get pods -n kube-system | grep ebs-csi | grep -i running >/dev/null 2>&1; then
    print_success "EBS CSI driver is running correctly"

    # Create test storage class and exit
    print_section "Setting up test storage class"
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
EOF
    print_success "Storage class 'ebs-sc' created"
    print_success "EBS CSI driver is already set up and working"
    exit 0
  else
    print_warning "EBS CSI driver add-on is installed but pods may not be running correctly"
    print_warning "Will attempt to fix this by recreating the add-on with proper IAM role"

    # Delete the add-on so we can reinstall it
    echo "Deleting existing add-on..."
    aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --region ${REGION}

    # Wait for deletion to complete
    echo "Waiting for add-on deletion to complete..."
    aws eks wait addon-deleted --cluster-name ${CLUSTER_NAME} --addon-name aws-ebs-csi-driver --region ${REGION}
  fi
fi

# -----------------
# Set up OIDC provider
# -----------------
print_section "Setting up OIDC provider for IAM roles"

# Get OIDC provider URL
OIDC_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: ${OIDC_ID}"

# Check if OIDC provider already exists
if ! aws iam list-open-id-connect-providers | grep ${OIDC_ID} >/dev/null 2>&1; then
  echo "Setting up OIDC provider..."
  aws eks associate-iam-oidc-provider --cluster-name ${CLUSTER_NAME} --region ${REGION} --approve
  print_success "OIDC provider created"
else
  print_success "OIDC provider already exists"
fi

# -----------------
# Create IAM role for EBS CSI Driver
# -----------------
print_section "Setting up IAM role for EBS CSI driver"

# Create the trust policy document
echo "Creating trust policy document..."
cat >ebs-csi-iam-policy-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Check if the role already exists
if aws iam get-role --role-name ${IAM_ROLE_NAME} >/dev/null 2>&1; then
  print_warning "IAM role '${IAM_ROLE_NAME}' already exists"
  echo "Updating the trust policy..."
  aws iam update-assume-role-policy --role-name ${IAM_ROLE_NAME} --policy-document file://ebs-csi-iam-policy-trust.json
else
  echo "Creating IAM role..."
  aws iam create-role --role-name ${IAM_ROLE_NAME} --assume-role-policy-document file://ebs-csi-iam-policy-trust.json
fi

# Attach the required policy
echo "Attaching policy to role..."
aws iam attach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn ${POLICY_ARN}

print_success "IAM role setup complete"

# -----------------
# Install EBS CSI Driver add-on
# -----------------
print_section "Installing EBS CSI Driver add-on"

# Get the service account role ARN
ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${IAM_ROLE_NAME}"
echo "Service account role ARN: ${ROLE_ARN}"

# Install the add-on
echo "Creating EBS CSI driver add-on..."
aws eks create-addon \
  --cluster-name ${CLUSTER_NAME} \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn ${ROLE_ARN} \
  --region ${REGION}

# Wait for add-on to be active
echo "Waiting for EBS CSI driver add-on to be active..."
aws eks wait addon-active \
  --cluster-name ${CLUSTER_NAME} \
  --addon-name aws-ebs-csi-driver \
  --region ${REGION}

print_success "EBS CSI driver add-on installed"

# -----------------
# Verify installation
# -----------------
print_section "Verifying EBS CSI driver installation"

# Check for running pods (with retry)
MAX_ATTEMPTS=10
ATTEMPT=1
while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "Checking for EBS CSI driver pods (attempt $ATTEMPT/$MAX_ATTEMPTS)..."

  if kubectl get pods -n kube-system | grep ebs-csi | grep -i running >/dev/null 2>&1; then
    print_success "EBS CSI driver pods are running"
    break
  fi

  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    print_warning "EBS CSI driver pods are not yet running. They may still be starting up."
    print_warning "You can check status later with: kubectl get pods -n kube-system | grep ebs-csi"
  fi

  ATTEMPT=$((ATTEMPT + 1))
  sleep 10
done

# Show the pods
echo "EBS CSI driver pods:"
kubectl get pods -n kube-system | grep ebs-csi

# -----------------
# Create test storage class
# -----------------
print_section "Setting up storage class"

echo "Creating 'ebs-sc' storage class..."
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
EOF

print_success "Storage class 'ebs-sc' created"

# -----------------
# Test PVC creation (optional)
# -----------------
print_section "Testing PVC creation (optional)"

read -p "Do you want to test creating a PVC and Pod to verify the setup? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Creating test PVC..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-test-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-sc
  resources:
    requests:
      storage: 4Gi
EOF

  echo "Creating test pod that uses the PVC..."
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ebs-test-pod
spec:
  containers:
  - name: ebs-test
    image: nginx
    volumeMounts:
    - mountPath: "/usr/share/nginx/html"
      name: ebs-volume
  volumes:
  - name: ebs-volume
    persistentVolumeClaim:
      claimName: ebs-test-claim
EOF

  echo "Waiting for PVC to be bound..."
  ATTEMPT=1
  while [ $ATTEMPT -le 10 ]; do
    if kubectl get pvc ebs-test-claim | grep Bound >/dev/null 2>&1; then
      print_success "PVC successfully bound"
      echo "PVC status:"
      kubectl get pvc ebs-test-claim
      break
    fi

    if [ $ATTEMPT -eq 10 ]; then
      print_warning "PVC not yet bound. It may still be provisioning."
      echo "Current PVC status:"
      kubectl get pvc ebs-test-claim
    fi

    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
  done

  echo "Waiting for test pod to be running..."
  ATTEMPT=1
  while [ $ATTEMPT -le 12 ]; do
    if kubectl get pod ebs-test-pod | grep Running >/dev/null 2>&1; then
      print_success "Test pod is running with the EBS volume attached"
      echo "Pod status:"
      kubectl get pod ebs-test-pod
      break
    fi

    if [ $ATTEMPT -eq 12 ]; then
      print_warning "Pod not yet running. Check status with: kubectl describe pod ebs-test-pod"
      echo "Current pod status:"
      kubectl get pod ebs-test-pod
    fi

    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
  done

  # Clean up test resources
  read -p "Do you want to clean up the test resources? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleaning up test resources..."
    kubectl delete pod ebs-test-pod
    kubectl delete pvc ebs-test-claim
    print_success "Test resources cleaned up"
  fi
fi

# -----------------
# Summary
# -----------------
print_section "Setup Summary"
echo "EBS CSI driver add-on installed in cluster: ${CLUSTER_NAME}"
echo "IAM role created/updated: ${IAM_ROLE_NAME}"
echo "Storage class created: ebs-sc"
echo
echo "You can now use the 'ebs-sc' storage class in your PVCs:"
echo
echo "Example PVC:"
echo "-----------"
echo "apiVersion: v1"
echo "kind: PersistentVolumeClaim"
echo "metadata:"
echo "  name: my-pvc"
echo "spec:"
echo "  accessModes:"
echo "    - ReadWriteOnce"
echo "  storageClassName: ebs-sc"
echo "  resources:"
echo "    requests:"
echo "      storage: 10Gi"

print_success "EBS CSI driver setup complete!"

# Clean up temporary files
rm -f ebs-csi-iam-policy-trust.json
