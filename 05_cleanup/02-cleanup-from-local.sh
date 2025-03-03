#!/bin/bash

# local-cleanup.sh
# Script to clean up Terraform-managed infrastructure (EC2 workstation and Terraform backend)
# Run this script from the 05_cleanup directory

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
# AWS Region - change if you used a different region
REGION="us-east-1"

# Determine project root directory (assuming this script is in the 05_cleanup directory)
SCRIPT_DIR=$(pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Terraform directories
TERRAFORM_BACKEND_DIR="${PROJECT_ROOT}/00_terraform_backend"
EC2_WORKSTATION_DIR="${PROJECT_ROOT}/01_ec2_workstation"

# Verify directory structure
echo "Script directory: $SCRIPT_DIR"
echo "Project root directory: $PROJECT_ROOT"
echo "EC2 workstation directory: $EC2_WORKSTATION_DIR"
echo "Terraform backend directory: $TERRAFORM_BACKEND_DIR"

# -----------------
# Prerequisites check
# -----------------
print_section "Checking Prerequisites"

# Check for required commands
if ! command -v terraform &>/dev/null; then
  print_error "terraform could not be found. Please make sure it's installed."
  exit 1
fi

if ! command -v aws &>/dev/null; then
  print_warning "aws CLI could not be found. Some verification steps will be skipped."
  AWS_MISSING=true
else
  # Check AWS credentials
  echo "Checking AWS credentials..."
  if ! aws sts get-caller-identity &>/dev/null; then
    print_warning "AWS credentials not configured or invalid."
    print_warning "Some verification steps will be skipped, but Terraform should still work if your credentials are configured in your AWS config files."
    AWS_MISSING=true
  else
    print_success "AWS credentials verified"
  fi
fi

# -----------------
# Verify EKS cluster is deleted
# -----------------
print_section "Verifying EKS Cluster Status"

if [ "$AWS_MISSING" != true ]; then
  # Check if EKS cluster exists
  if aws eks describe-cluster --name eks-mundos-e --region ${REGION} &>/dev/null; then
    print_warning "EKS cluster 'eks-mundos-e' still exists!"

    if prompt_continue "Do you want to continue anyway? (It's recommended to delete the EKS cluster first)" false; then
      echo "Continuing with Terraform infrastructure cleanup..."
    else
      print_error "Please run ec2-cleanup.sh on the EC2 workstation first to delete the EKS cluster"
      exit 1
    fi
  else
    print_success "EKS cluster 'eks-mundos-e' not found or already deleted"
  fi
else
  print_warning "AWS CLI not available. Skipping EKS cluster verification."

  if ! prompt_continue "Did you already run ec2-cleanup.sh on the EC2 workstation to delete the EKS cluster?"; then
    print_error "Please run ec2-cleanup.sh on the EC2 workstation first to delete the EKS cluster"
    exit 1
  fi
fi

# -----------------
# Step 1: Delete EC2 workstation using Terraform
# -----------------
print_section "Step 1: Deleting EC2 workstation"

# Check if EC2 workstation directory exists
if [ -d "${EC2_WORKSTATION_DIR}" ]; then
  echo "Found EC2 workstation Terraform directory at: ${EC2_WORKSTATION_DIR}"

  if prompt_continue "Do you want to destroy the EC2 workstation?"; then
    cd "${EC2_WORKSTATION_DIR}"
    echo "Changed directory to: $(pwd)"

    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
      echo "Initializing Terraform..."
      terraform init || {
        print_error "Failed to initialize Terraform"
        exit 1
      }
    fi

    # Explicitly show what's about to be destroyed
    echo "Showing resources that will be destroyed:"
    terraform plan -destroy

    # Confirm before proceeding
    if prompt_continue "Proceed with destroying EC2 workstation?" false; then
      echo "Destroying EC2 workstation with Terraform (this may take a few minutes)..."

      # Run terraform destroy with auto-approve to avoid hanging
      terraform destroy -auto-approve

      if [ $? -eq 0 ]; then
        print_success "EC2 workstation destroyed successfully"
      else
        print_error "Failed to destroy EC2 workstation"

        # Show current state
        echo "Current Terraform state:"
        terraform state list

        # Offer manual alternatives
        echo "You can try to manually destroy the resources with:"
        echo "cd ${EC2_WORKSTATION_DIR} && terraform destroy"

        if prompt_continue "Do you want to continue with the rest of the cleanup?" false; then
          echo "Continuing with cleanup..."
        else
          print_error "Cleanup aborted"
          exit 1
        fi
      fi
    else
      print_warning "EC2 workstation destruction skipped"
    fi

    cd "${SCRIPT_DIR}"
  else
    print_warning "EC2 workstation destruction skipped"
  fi
else
  print_error "EC2 workstation Terraform directory not found at: ${EC2_WORKSTATION_DIR}"
  echo "Directory contents of project root:"
  ls -la "${PROJECT_ROOT}"

  # Try to find the directory
  echo "Searching for EC2 workstation directory..."
  find "${PROJECT_ROOT}" -name "01_ec2_workstation" -type d

  if prompt_continue "Would you like to enter the directory path manually?" false; then
    read -p "Enter the full path to the EC2 workstation directory: " EC2_DIR_PATH
    if [ -d "$EC2_DIR_PATH" ]; then
      echo "Directory found, proceeding with cleanup..."
      cd "$EC2_DIR_PATH"

      # Check if Terraform is initialized
      if [ ! -d ".terraform" ]; then
        echo "Initializing Terraform..."
        terraform init
      fi

      echo "Destroying EC2 workstation with Terraform..."
      terraform destroy -auto-approve

      if [ $? -eq 0 ]; then
        print_success "EC2 workstation destroyed successfully"
      else
        print_error "Failed to destroy EC2 workstation"
      fi

      cd "${SCRIPT_DIR}"
    else
      print_error "Directory not found: $EC2_DIR_PATH"
      print_warning "Skipping EC2 workstation destruction"
    fi
  else
    print_warning "Skipping EC2 workstation destruction"
  fi
fi

# -----------------
# Step 2: Delete Terraform backend resources
# -----------------
print_section "Step 2: Deleting Terraform backend resources"

# Check if Terraform backend directory exists
if [ -d "${TERRAFORM_BACKEND_DIR}" ]; then
  echo "Found Terraform backend directory at: ${TERRAFORM_BACKEND_DIR}"

  if prompt_continue "Do you want to destroy the Terraform backend resources (S3 bucket and DynamoDB table)?"; then
    cd "${TERRAFORM_BACKEND_DIR}"
    echo "Changed directory to: $(pwd)"

    # Check if Terraform is initialized
    if [ ! -d ".terraform" ]; then
      echo "Initializing Terraform..."
      terraform init || {
        print_error "Failed to initialize Terraform for backend resources"
        exit 1
      }
    fi

    # Get S3 bucket name from Terraform state or variables
    S3_BUCKET=$(grep 'name_of_s3_bucket' variables.tf | grep -o '".*"' | sed 's/"//g')
    DYNAMODB_TABLE=$(grep 'dynamo_db_table_name' variables.tf | grep -o '".*"' | sed 's/"//g')

    echo "S3 bucket to be deleted: ${S3_BUCKET}"
    echo "DynamoDB table to be deleted: ${DYNAMODB_TABLE}"

    if prompt_continue "WARNING: This will delete all Terraform state files. Are you absolutely sure?" false; then
      # Emptying S3 bucket first to avoid deletion errors
      if [ "$AWS_MISSING" != true ]; then
        echo "Emptying S3 bucket first..."
        aws s3 rm s3://${S3_BUCKET} --recursive || print_warning "Failed to empty S3 bucket. It might not exist or you may not have permission."
      else
        echo "AWS CLI not available. Attempting to destroy without emptying bucket first."
        echo "If this fails, you may need to manually empty the bucket from the AWS console."
      fi

      echo "Destroying Terraform backend resources..."
      terraform destroy -auto-approve

      if [ $? -eq 0 ]; then
        print_success "Terraform backend resources destroyed successfully"
      else
        print_error "Failed to destroy Terraform backend resources"

        if [ "$AWS_MISSING" != true ]; then
          print_warning "You may need to manually delete the S3 bucket and DynamoDB table from the AWS console."
          print_warning "S3 bucket: ${S3_BUCKET}"
          print_warning "DynamoDB table: ${DYNAMODB_TABLE}"
        fi
      fi
    else
      print_warning "Terraform backend destruction skipped"
    fi

    cd "${SCRIPT_DIR}"
  else
    print_warning "Terraform backend destruction skipped"
  fi
else
  print_warning "Terraform backend directory not found at: ${TERRAFORM_BACKEND_DIR}"
  echo "Directory contents of project root:"
  ls -la "${PROJECT_ROOT}"
fi

# -----------------
# Final cleanup and summary
# -----------------
print_section "Cleanup Summary"

# Check for any remaining AWS resources
if [ "$AWS_MISSING" != true ]; then
  echo "Checking for any remaining EC2 instances with the tag Name=DevOps-Workstation..."
  REMAINING_EC2=$(aws ec2 describe-instances --region ${REGION} --filters "Name=tag:Name,Values=DevOps-Workstation" "Name=instance-state-name,Values=running,stopped,pending,stopping" --query 'Reservations[*].Instances[*].InstanceId' --output text)

  if [ -n "$REMAINING_EC2" ]; then
    print_warning "Remaining EC2 instances found: ${REMAINING_EC2}"
    echo "You may want to manually terminate these instances if they are no longer needed."

    # Offer manual termination
    if prompt_continue "Would you like to terminate these instances now?" false; then
      for instance in $REMAINING_EC2; do
        echo "Terminating instance $instance..."
        aws ec2 terminate-instances --region ${REGION} --instance-ids $instance
        echo "Waiting for termination..."
        aws ec2 wait instance-terminated --region ${REGION} --instance-ids $instance
        print_success "Instance $instance terminated"
      done
    fi
  else
    print_success "No DevOps-Workstation EC2 instances found in region ${REGION}"
  fi

  if [ -n "$S3_BUCKET" ]; then
    echo "Checking for S3 bucket '${S3_BUCKET}'..."
    if aws s3api head-bucket --bucket ${S3_BUCKET} 2>/dev/null; then
      print_warning "S3 bucket '${S3_BUCKET}' still exists"
      echo "You may want to manually delete this bucket if it is no longer needed."

      # Offer manual deletion
      if prompt_continue "Would you like to delete this bucket now?" false; then
        echo "Emptying and deleting S3 bucket ${S3_BUCKET}..."
        aws s3 rm s3://${S3_BUCKET} --recursive
        aws s3api delete-bucket --bucket ${S3_BUCKET}
        print_success "S3 bucket deleted"
      fi
    else
      print_success "S3 bucket '${S3_BUCKET}' not found or already deleted"
    fi
  fi

  if [ -n "$DYNAMODB_TABLE" ]; then
    echo "Checking for DynamoDB table '${DYNAMODB_TABLE}'..."
    if aws dynamodb describe-table --table-name ${DYNAMODB_TABLE} --region ${REGION} 2>/dev/null; then
      print_warning "DynamoDB table '${DYNAMODB_TABLE}' still exists"
      echo "You may want to manually delete this table if it is no longer needed."

      # Offer manual deletion
      if prompt_continue "Would you like to delete this table now?" false; then
        echo "Deleting DynamoDB table ${DYNAMODB_TABLE}..."
        aws dynamodb delete-table --table-name ${DYNAMODB_TABLE} --region ${REGION}
        print_success "DynamoDB table deleted"
      fi
    else
      print_success "DynamoDB table '${DYNAMODB_TABLE}' not found or already deleted"
    fi
  fi
fi

print_section "Cleanup Complete"

echo "The following resources have been cleaned up:"
echo "✓ EC2 workstation (Terraform-managed)"
echo "✓ Terraform backend resources (S3 bucket, DynamoDB table)"

echo -e "\n${GREEN}Local cleanup script execution completed${NC}"
echo "Note: Some AWS resources might still exist if they couldn't be automatically detected or deleted."
echo "It's recommended to check your AWS console to ensure all resources have been properly cleaned up."

print_success "Thank you for using the cleanup script!"
