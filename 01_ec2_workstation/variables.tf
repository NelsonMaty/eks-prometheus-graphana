variable "additional_ssh_keys" {
  description = "List of additional SSH public keys to add to the instance"
  type        = list(string)
  default     = []
} # Variables

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "DevOps-Workstation"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = "pin"
}

variable "ssh_key_path" {
  description = "Path to the SSH public key file"
  type        = string
  default     = "~/.ssh/pin.pub"
}

variable "volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 20
}
