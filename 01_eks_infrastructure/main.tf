module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"

  vpc_id     = aws_vpc.vpc.id
  subnet_ids = aws_subnet.subnet[*].id

  eks_managed_node_groups = {
    main = {
      name           = "worker-group"
      instance_types = ["t2.small"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_vpc.vpc,
    aws_subnet.subnet
  ]
}
