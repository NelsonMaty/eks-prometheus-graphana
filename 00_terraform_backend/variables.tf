variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "name_of_s3_bucket" {
  description = "Name of S3 bucket for terraform state"
  type        = string
  default     = "rios.nelson.mundose"
}

variable "dynamo_db_table_name" {
  description = "Name of DynamoDB table for terraform state locking"
  type        = string
  default     = "terraformstatelock"
}

