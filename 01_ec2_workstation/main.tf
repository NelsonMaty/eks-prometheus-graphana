terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0.0"
    }
  }

  backend "s3" {
    bucket         = "rios.nelson.mundose"
    key            = "terraform/ec2-workstation/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraformstatelock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

# AMI - Ubuntu 22.04 LTS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
