# DevOps Integration Project

This repository contains the infrastructure setup for a complete DevOps environment with AWS EKS, Terraform, monitoring tools, and more. The project is structured to guide you through setting up a cloud-based Kubernetes environment with proper monitoring and deployment capabilities.

## Project Structure

```
.
├── 00_terraform_backend/     # S3 and DynamoDB for Terraform state
├── 01_ec2_workstation/       # EC2 instance setup as a DevOps workstation
├── (additional directories will be added as the project grows)
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

Once connected to the EC2 instance, create an EKS cluster:

```bash
# Create the EKS cluster
eksctl create cluster \
  --name eks-mundos-e \
  --region us-east-1 \
  --node-type t3.small \
  --nodes 3 \
  --with-oidc \
  --ssh-access \
  --ssh-public-key pin \
  --managed \
  --full-ecr-access \
  --zones us-east-1a,us-east-1b,us-east-1c
```

This will take approximately 15-20 minutes to complete.

## Step 5: Verify Cluster Access

Once the cluster is created, verify that kubectl is properly configured:

```bash
# Verify that kubectl is configured to use your cluster
kubectl get nodes

# You should see your 3 nodes listed as Ready
```

## Step 6: Deploy NGINX Test Application

Deploy a basic NGINX application to test the cluster:

```bash
# Create a NGINX deployment
kubectl create deployment nginx --image=nginx

# Expose the deployment with a LoadBalancer service
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Check the service
kubectl get services

# Wait until the EXTERNAL-IP is populated (not <pending>)
```

You can access the NGINX test application by visiting the EXTERNAL-IP address in your browser.

## Step 7: Install EBS CSI Driver

Before installing monitoring tools, we need to install the AWS EBS CSI driver to support persistent volumes:

```bash
# Install the AWS EBS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.20"

# Verify the driver pods are running
kubectl get pods -n kube-system | grep ebs
```

If the EBS CSI driver pods are stuck in pending state, you may need to add the EBS policy to your node IAM role:

```bash
# Get the node IAM role
NODE_GROUP=$(eksctl get nodegroup --cluster eks-mundos-e -o json | jq -r '.[0].NodeInstanceRoleARN')

# Attach the EBS policy to the role
aws iam attach-role-policy --role-name $(echo $NODE_GROUP | cut -d "/" -f 2) --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

## Step 8: Install Prometheus

Install Prometheus for cluster monitoring:

```bash
# Add the Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace for Prometheus
kubectl create namespace prometheus

# Install Prometheus
helm install prometheus prometheus-community/prometheus \
  --namespace prometheus \
  --set alertmanager.persistentVolume.storageClass="gp2" \
  --set server.persistentVolume.storageClass="gp2"

# Verify Prometheus pods are running
kubectl get pods -n prometheus

# Access Prometheus dashboard (port forwarding)
kubectl port-forward -n prometheus svc/prometheus-server 9090:80
```

With port forwarding, you can access the Prometheus dashboard at http://localhost:9090 in your browser.

## Step 9: Install Grafana

Install Grafana for visualization:

```bash
# Create namespace for Grafana
kubectl create namespace grafana

# Add the Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Create a values file for Grafana
mkdir -p ${HOME}/environment/grafana
cat << EOF > ${HOME}/environment/grafana/grafana.yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.prometheus.svc.cluster.local
      access: proxy
      isDefault: true
EOF

# Install Grafana
helm install grafana grafana/grafana \
  --namespace grafana \
  --set persistence.storageClassName="gp2" \
  --set persistence.enabled=true \
  --set adminPassword='EKS!sAWSome' \
  --values ${HOME}/environment/grafana/grafana.yaml \
  --set service.type=LoadBalancer

# Get the Grafana load balancer URL
export ELB=$(kubectl get svc -n grafana grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Grafana URL: http://$ELB"

# Get the Grafana admin password
kubectl get secret --namespace grafana grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
```

Access Grafana dashboard using the ELB URL and log in with:
- Username: admin
- Password: EKS!sAWSome (or the decoded password from the above command)

## Step 10: Import Grafana Dashboards

After logging into Grafana, import these useful Kubernetes dashboards:

1. From the left sidebar, click the "+" icon and select "Import"
2. Enter the dashboard ID: 3119 (Kubernetes: Cluster Monitoring)
3. Select "Prometheus" as the data source
4. Click "Import"
5. Repeat for dashboard ID: 6417 (Kubernetes: Pod Monitoring)

## Step 11: Cleanup

When you're done with the project, clean up all resources to avoid unwanted AWS charges:

```bash
# Delete Grafana and Prometheus
helm uninstall prometheus --namespace prometheus
kubectl delete ns prometheus
helm uninstall grafana --namespace grafana
kubectl delete ns grafana
rm -rf ${HOME}/environment/grafana

# Delete the EKS cluster
eksctl delete cluster --name eks-mundos-e

# Exit the EC2 instance
exit

# Navigate to the EC2 workstation directory
cd 01_ec2_workstation

# Delete the EC2 instance
terraform destroy

# Navigate to the Terraform backend directory
cd ../00_terraform_backend

# Delete the S3 bucket and DynamoDB table
terraform destroy
```

## Troubleshooting

### EBS CSI Driver Issues

If the EBS CSI driver pods are stuck in pending state, you likely need to add the Amazon EBS CSI Driver Policy to your node IAM role as described in Step 7.

### Accessing Services

- For services exposed with LoadBalancer, wait until the EXTERNAL-IP is populated
- For port forwarding, ensure you're using the correct namespace and service name

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
