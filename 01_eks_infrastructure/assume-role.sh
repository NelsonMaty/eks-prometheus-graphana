#!/bin/bash
set -eo pipefail

# Check dependencies
command -v aws >/dev/null 2>&1 || { echo >&2 "AWS CLI required but not found. Exiting."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "Terraform required but not found. Exiting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq required but not found. Exiting."; exit 1; }

# Initialize and apply Terraform config
echo "Applying Terraform configuration..."
cd 01_eks_infrastructure
terraform init
terraform apply -auto-approve

# Get required outputs
ROLE_ARN=$(terraform output -raw role_arn)
CLUSTER_NAME=$(terraform output -raw cluster_name)
cd ..

# Assume the role and get temporary credentials
echo "Assuming EKS admin role..."
SESSION=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name eks-admin \
  --duration-seconds 3600)

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo "$SESSION" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$SESSION" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$SESSION" | jq -r .Credentials.SessionToken)

# Configure EKS access
echo "Configuring kubectl..."
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region us-east-1

# Verify access
echo "Testing cluster access..."
kubectl get nodes

echo -e "\n\033[1;32mSuccess! You now have temporary admin access to the EKS cluster for 1 hour.\033[0m"
echo "To clean up resources later, run: cd 01_eks_infrastructure && terraform destroy -auto-approve"
