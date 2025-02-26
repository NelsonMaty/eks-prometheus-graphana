# Configure the AWS provider with the specified region
provider "aws" {
  region = var.region
}

# Fetch available AWS availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Select the first two availability zones for use in the VPC
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# Create a VPC using the Terraform AWS VPC module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"

  # Name and CIDR block for the VPC
  name = var.name
  cidr = var.vpc_cidr

  # Assign subnets to availability zones
  azs             = local.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  intra_subnets   = var.intra_subnets

  # Enable NAT gateway for private subnets to access the internet
  enable_nat_gateway = true

  # Tag public subnets for external load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  # Tag private subnets for internal load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

