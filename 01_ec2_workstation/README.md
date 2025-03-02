# Terraform EC2 Deployment Workstation

This Terraform configuration creates an EC2 instance configured as a DevOps Deployment Workstation with all necessary tools pre-installed, as required for the DevOps Integration Project.

## Files Structure

```
.
├── generate-ssh-key.sh      # Script to generate SSH key
├── main.tf                  # Main Terraform configuration and provider setup
├── variables.tf             # Variable definitions
├── outputs.tf               # Output definitions
├── networking.tf            # Security groups and networking resources
├── iam.tf                   # IAM roles and policies
├── ssh.tf                   # SSH key configuration
├── instance.tf              # EC2 instance configuration
├── user_data.sh             # EC2 instance user data script
└── terraform.tfvars.example # Example variable values (copy to terraform.tfvars)
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed (v1.0.0 or later)
- AWS CLI installed and configured with appropriate credentials
- A terminal or command prompt

## Setup and Deployment

### 1. Generate SSH Key Pair

First, run the script to generate an SSH key pair:

```bash
./generate-ssh-key.sh
```

This will create the SSH key pair in your `~/.ssh/` directory:
- `~/.ssh/pin`: Private key (keep this secure)
- `~/.ssh/pin.pub`: Public key (used by Terraform)

### 2. Configure Variables (Optional)

Copy the example variables file and modify as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to customize:
- Instance type and size
- Region
- SSH key details
- Additional team member SSH keys

### 3. Initialize Terraform with Remote Backend

The configuration is set up to use a remote backend stored in an S3 bucket with DynamoDB for state locking. This ensures that your Terraform state is stored securely and can be shared across a team.

```bash
terraform init
```

Note: The backend configuration is already set up in the main.tf file to use:
- S3 bucket: rios.nelson.mundose
- Key path: terraform/ec2-workstation/terraform.tfstate
- DynamoDB table: terraformstatelock

### 4. Preview the Changes

```bash
terraform plan
```

### 5. Apply the Configuration

```bash
terraform apply
```

When prompted, type `yes` to confirm.

### 6. Connect to Your Instance

After the deployment completes, Terraform will output the SSH command to connect to your instance:

```bash
ssh -i ~/.ssh/pin ubuntu@<your-instance-ip>
```

## Team Collaboration

To add SSH keys for team members:

1. Edit `terraform.tfvars` and add public keys to the `additional_ssh_keys` list
2. Run `terraform apply` to update the instance

This will ensure all team members can access the EC2 instance.

## Installed Tools

The EC2 instance comes pre-installed with:

- AWS CLI
- Docker
- kubectl
- eksctl
- Helm
- k9s (Kubernetes CLI tool)
- kustomize

## Cleanup

To destroy all resources created by this configuration:

```bash
terraform destroy
```

When prompted, type `yes` to confirm.

## Notes

- The IAM role created has administrative access. For production use, you might want to restrict permissions.
- The security group allows SSH access from anywhere (0.0.0.0/0). For better security, consider restricting this to your IP address.
- The instance is created in the us-east-1 region by default. Modify the variables if you want to use a different region.
