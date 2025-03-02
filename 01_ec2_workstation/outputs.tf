output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.devops_workstation.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.devops_workstation.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = aws_instance.devops_workstation.public_dns
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/pin ubuntu@${aws_instance.devops_workstation.public_ip}"
}
