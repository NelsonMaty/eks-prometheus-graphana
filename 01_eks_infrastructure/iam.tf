resource "aws_iam_user" "eks_user" {
  name = "${var.cluster_name}-eks-user"
}

resource "aws_iam_role" "eks_admin_role" {
  name = "${var.cluster_name}-eks-admin-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.eks_user.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

