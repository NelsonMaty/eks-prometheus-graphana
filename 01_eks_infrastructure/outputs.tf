output "role_arn" {
  description = "ARN of the admin role"
  value       = aws_iam_role.eks_admin_role.arn
}

output "user_arn" {
  description = "ARN of the IAM user"
  value       = aws_iam_user.eks_user.arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}
