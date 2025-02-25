output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = aws_instance.bastion.public_ip
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "bastion_connection_command" {
  value = "ssh -i ~/.ssh/eks-bastion-key ec2-user@${aws_instance.bastion.public_ip}"
}
