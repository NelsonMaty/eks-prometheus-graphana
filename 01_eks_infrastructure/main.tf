# Deploy an Amazon EKS cluster using the Terraform AWS EKS module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.1"

  # Name of the EKS cluster
  cluster_name = var.name
  # Allow public access to the cluster API endpoint
  cluster_endpoint_public_access = true

  # Enable essential Kubernetes addons
  cluster_addons = {
    # - CoreDNS: Handles DNS-based service discovery within the cluster.
    coredns = {
      most_recent = true
    }
    # - Kube-Proxy: Maintains network rules for communication between pods.
    kube-proxy = {
      most_recent = true
    }
    # - VPC CNI: Manages pod networking using AWS VPC native networking.
    vpc-cni = {
      most_recent = true
    }
  }

  # Associate the cluster with the VPC and subnets
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # Default settings for managed node groups
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64" # Amazon Linux 2 AMI
    instance_types = ["t2.small"] # Instance type for worker nodes

    attach_cluster_primary_security_group = true
  }

  # Define a managed node group for the cluster
  eks_managed_node_groups = {
    main = {
      min_size     = 1 # Minimum number of worker nodes
      max_size     = 2 # Maximum number of worker nodes
      desired_size = 1 # Desired number of worker nodes

      instance_types = ["t2.small"] # Instance type for worker nodes
      capacity_type  = "SPOT"       # Use spot instances to reduce costs
    }
  }
}
