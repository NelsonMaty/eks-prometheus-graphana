#!/bin/bash

# Update system
apt-get update && apt-get upgrade -y

# Install general utilities
apt-get install -y apt-transport-https ca-certificates curl software-properties-common unzip jq git

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin
chmod +x /usr/local/bin/eksctl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install k9s (Kubernetes CLI tool)
curl -L https://github.com/derailed/k9s/releases/download/v0.26.7/k9s_Linux_amd64.tar.gz | tar xz -C /tmp
mv /tmp/k9s /usr/local/bin
chmod +x /usr/local/bin/k9s

# Install kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
mv kustomize /usr/local/bin/

# Create a welcome message
cat >/etc/motd <<'MOTD'
DevOps Workstation

This instance has been set up with the following tools:
- AWS CLI
- Docker
- kubectl
- eksctl
- Helm
- k9s
- kustomize

Ready for your DevOps journey!
MOTD

echo "Setup completed!"
