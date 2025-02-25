module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.cluster_name}-${var.environment}"
  cluster_version = "1.28"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  enable_irsa = true
  enable_cluster_creator_admin_permissions = true

  cluster_security_group_additional_rules = {
    ingress_from_bastion = {
      description              = "Allow bastion to API server"
      protocol                 = "tcp"
      from_port                = 443
      to_port                  = 443
      source_security_group_id = aws_security_group.bastion_sg.id
      type                     = "ingress"
    }
    ingress_http = {
      description = "Cluster ingress from ALB"
      protocol    = "tcp"
      from_port   = 80
      to_port     = 80
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    main = {
      instance_types = ["t3.small"]
      capacity_type  = "SPOT"
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      update_config = {
        max_unavailable = 1
      }
    }
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  authentication_mode = "API"
}
