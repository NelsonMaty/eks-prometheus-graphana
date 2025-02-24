resource "aws_iam_user" "eks_user" {
  name = "${var.cluster_name}-eks-user"
}

