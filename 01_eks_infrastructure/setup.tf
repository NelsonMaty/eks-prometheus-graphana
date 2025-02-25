terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.88.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
  my_ip    = chomp(data.http.my_ip.response_body)
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "http" "my_ip" {
  url = "https://api.ipify.org"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-${var.environment}"
  cidr = local.vpc_cidr

  azs            = local.azs
  public_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Environment                                 = var.environment
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_security_group" "bastion_sg" {
  name_prefix = "bastion-sg"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "bastion" {
  key_name   = "eks-bastion-key"
  public_key = file("~/.ssh/eks-bastion-key.pub")
}

resource "aws_instance" "bastion" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name      = aws_key_pair.bastion.key_name
  iam_instance_profile = aws_iam_instance_profile.bastion.name

  tags = {
    Name = "eks-bastion"
  }

  user_data = <<-EOT
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y docker jq
    sudo systemctl start docker
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl
  EOT
}
