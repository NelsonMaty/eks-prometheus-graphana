
# Define the name of the EKS cluster
variable "name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "nelson-cluster"
}

# Define the AWS region
variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# Define the CIDR block for the VPC
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.123.0.0/16"
}

# Define the CIDR blocks for public subnets
variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.123.1.0/24", "10.123.2.0/24"]
}

# Define the CIDR blocks for private subnets
variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.123.3.0/24", "10.123.4.0/24"]
}

# Define the CIDR blocks for intra subnets
variable "intra_subnets" {
  description = "CIDR blocks for intra subnets"
  type        = list(string)
  default     = ["10.123.5.0/24", "10.123.6.0/24"]
}
