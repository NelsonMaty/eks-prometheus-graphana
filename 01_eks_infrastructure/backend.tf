terraform {
  required_version = "~> 1.10.0"

  backend "s3" {
    bucket         = "rios.nelson.mundose"
    region         = "us-east-1"
    key            = "infrastructure.tfstate"
    dynamodb_table = "terraformstatelock"
  }
}
