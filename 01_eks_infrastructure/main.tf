module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.cluster_name}-${var.environment}"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  authentication_mode = "API"
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    eks-admin-user = {
      principal_arn   = aws_iam_user.eks_user.arn
      policy_associations = {
        cluster-admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    main = {
      name = "worker-group-${var.environment}"
      instance_types = ["t2.micro"]
      min_size     = 1
      max_size     = 2
      desired_size = 1
      tags = {
        Environment = var.environment
      }
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
