# DevOps Integration Project

This repository contains the infrastructure setup for a complete DevOps environment with AWS EKS, Terraform, monitoring tools, and more. The project is structured to guide you through setting up a cloud-based Kubernetes environment with proper monitoring and deployment capabilities.

## Project Structure

```
.
├── 00_terraform_backend/     # S3 and DynamoDB for Terraform state
├── 01_ec2_workstation/       # EC2 instance setup as a DevOps workstation
├── 02_eks_creation/          # Scripts to create and configure EKS cluster
├── 03_prometheus_setup/      # Setup scripts for Prometheus monitoring
├── 04_grafana_setup/         # Setup scripts for Grafana dashboards
└── 05_cleanup/               # Cleanup scripts to remove all resources
```

## Prerequisites

- [AWS Account](https://aws.amazon.com/)
- [AWS CLI](https://aws.amazon.com/cli/) configured on your local machine
- [Terraform](https://www.terraform.io/downloads.html) (v1.10.0 or higher)
- Basic knowledge of AWS, Terraform, and Kubernetes

## Step 1: Set Up Terraform Backend

First, we'll configure an S3 bucket and DynamoDB table for Terraform state management:

```bash
# Navigate to the Terraform backend directory
cd 00_terraform_backend

# Initialize Terraform
terraform init

# Apply the configuration
terraform apply
```

This will create:
- S3 bucket for Terraform state files
- DynamoDB table for state locking

## Step 2: Deploy the EC2 Workstation

Next, we'll create an EC2 instance with all the necessary DevOps tools pre-installed:

```bash
# Navigate to the EC2 workstation directory
cd ../01_ec2_workstation

# Generate an SSH key if you don't have one already
./generate-ssh-key.sh

# Initialize Terraform with the remote backend
terraform init

# Deploy the EC2 instance
terraform apply
```

The output will include the SSH command to connect to your EC2 instance. It will look something like this:
```
ssh -i ~/.ssh/pin ubuntu@<your-instance-public-ip>
```

## Step 3: Connect to the EC2 Workstation

Use the SSH command provided in the Terraform output to connect to your EC2 instance:

```bash
ssh -i ~/.ssh/pin ubuntu@<your-instance-public-ip>
```

## Step 4: Create an EKS Cluster

Once connected to the EC2 instance, run the EKS initialization script:

```bash
# Navigate to the EKS creation directory
cd ~/02_eks_creation

# Make the script executable
chmod +x initialize-eks.sh

# Run the script
./initialize-eks.sh
```

The script will:
- Create the EKS cluster with 3 nodes in different availability zones
- Configure kubectl to connect to the cluster
- Deploy a basic NGINX application with a LoadBalancer
- Provide you with the URL to access NGINX

## Step 5: Set Up AWS EBS CSI Driver

Before setting up Prometheus and Grafana, we need to install the AWS EBS CSI driver for persistent volumes:

```bash
# Navigate to the Prometheus setup directory
cd ~/03_prometheus_setup

# Make the script executable
chmod +x 01-persistance-setup.sh

# Run the script
./01-persistance-setup.sh
```

This script will:
- Set up the necessary IAM roles and policies
- Install the AWS EBS CSI driver as an EKS add-on
- Create a storage class for Prometheus and Grafana persistent volumes

## Step 6: Install Prometheus

Install Prometheus for cluster monitoring:

```bash
# Make the Prometheus setup script executable
chmod +x 02-prometheus-setup.sh

# Run the script
./02-prometheus-setup.sh
```

This script will:
- Create a namespace for Prometheus
- Deploy Prometheus using Helm
- Configure persistent storage for Prometheus
- Create a LoadBalancer service for external access
- Provide you with the URL to access the Prometheus dashboard

## Step 7: Install Grafana

Install Grafana for visualization:

```bash
# Navigate to the Grafana setup directory
cd ~/04_grafana_setup

# Make the script executable
chmod +x grafana-setup.sh

# Run the script
./grafana-setup.sh
```

This script will:
- Create a namespace for Grafana
- Deploy Grafana using Helm
- Configure Prometheus as a data source
- Import Kubernetes dashboards (IDs: 3119 and 6417)
- Create a LoadBalancer service for external access
- Provide you with the URL and login credentials for Grafana

Access Grafana dashboard using the provided URL and log in with:
- Username: admin
- Password: EKS!sAWSome (or as configured in the script)

## Step 8: Explore Grafana Dashboards

After logging into Grafana, you can explore the pre-imported dashboards:

1. Click on the "Dashboards" menu in the left sidebar
2. Select "Browse"
3. Navigate to the "Kubernetes" folder
4. Explore the "Kubernetes Cluster Monitoring" and "Kubernetes Pod Monitoring" dashboards

## Step 9: Cleanup

When you're done with the project, clean up all resources to avoid unwanted AWS charges.

First, clean up Kubernetes resources and delete the EKS cluster from the EC2 instance:

```bash
# Navigate to the cleanup directory
cd ~/05_cleanup

# Make the script executable
chmod +x 01-cleanup-from-ec2.sh

# Run the script
./01-cleanup-from-ec2.sh
```

Then, back on your local machine, clean up the Terraform resources:

```bash
# Navigate to the cleanup directory
cd 05_cleanup

# Make the script executable
chmod +x 02-cleanup-from-local.sh

# Run the script
./02-cleanup-from-local.sh
```

This will clean up:
- Grafana and Prometheus resources
- EKS cluster and its resources
- EC2 workstation
- Terraform backend resources (S3 bucket and DynamoDB table)

## Troubleshooting

### EBS CSI Driver Issues

If the EBS CSI driver pods are stuck in pending state, the script in `03_prometheus_setup/01-persistance-setup.sh` should handle this by:
- Creating the necessary IAM roles
- Attaching the required policies
- Setting up the EBS CSI driver as an EKS add-on

### Accessing Services

- For services exposed with LoadBalancer, the scripts will provide you with the URLs
- If LoadBalancer URLs are not available, you can use port forwarding:
  ```bash
  # For Prometheus
  kubectl port-forward -n prometheus svc/prometheus-server 9090:80 --address 0.0.0.0
  
  # For Grafana
  kubectl port-forward -n grafana svc/grafana 3000:80 --address 0.0.0.0
  ```

### Cluster Creation Failures

If cluster creation fails, examine the CloudFormation events in the AWS console for detailed error messages. Common issues include:
- IAM permission problems
- Service quotas exceeded
- Networking constraints

## Additional Resources

- [eksctl Documentation](https://eksctl.io/introduction/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Prometheus Documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
