#!/bin/bash
set -eo pipefail

# Initialize and apply Terraform config
echo "Applying Terraform configuration..."
terraform init
terraform apply -auto-approve

# Get required outputs
ROLE_ARN=$(terraform output -raw role_arn)
CLUSTER_NAME=$(terraform output -raw cluster_name)
USER_NAME=$(terraform output -raw user_arn | cut -d'/' -f2)

echo "Cleaning up existing access keys..."
EXISTING_KEYS=$(aws iam list-access-keys --user-name $USER_NAME --query 'AccessKeyMetadata[].AccessKeyId' --output text)
for key in $EXISTING_KEYS; do
  echo "Deleting key: $key"
  aws iam delete-access-key --user-name $USER_NAME --access-key-id $key
done

# Create temporary credentials for the IAM user
echo "Creating temporary user credentials..."
TEMP_CREDS=$(aws iam create-access-key --user-name $USER_NAME --output json)
ACCESS_KEY=$(echo "$TEMP_CREDS" | jq -r .AccessKey.AccessKeyId)
SECRET_KEY=$(echo "$TEMP_CREDS" | jq -r .AccessKey.SecretAccessKey)

MAX_RETRIES=3
RETRY_DELAY=5 # seconds

echo "Assuming EKS admin role..."
for ((i = 1; i <= $MAX_RETRIES; i++)); do
  SESSION=$(AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
    aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name eks-admin \
    --duration-seconds 3600 \
    --output json 2>&1) && break

  echo "Attempt $i failed: $SESSION"
  if [ $i -eq $MAX_RETRIES ]; then
    echo "Failed to assume role after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "Retrying in $RETRY_DELAY seconds..."
  sleep $RETRY_DELAY
done

# Add credential validation
if ! echo "$SESSION" | jq -e '.Credentials' >/dev/null; then
  echo "Failed to assume role. AWS response:"
  echo "$SESSION"
  exit 1
fi

# Cleanup temporary credentials immediately
echo "Cleaning up temporary credentials..."
aws iam delete-access-key --user-name $USER_NAME --access-key-id $ACCESS_KEY

# Export session credentials
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

echo -e "\n\033[1;32mSuccess! Temporary admin access granted for 1 hour.\033[0m"
