# EC2 instance configuration
locals {
  # Build SSH keys script if there are additional keys to add
  ssh_script = <<EOF
#!/bin/bash

# Append additional SSH keys to authorized_keys
mkdir -p /home/ubuntu/.ssh
echo "${join("\n", var.additional_ssh_keys)}" >> /home/ubuntu/.ssh/authorized_keys
chmod 700 /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

EOF

  # Determine if we need to include the SSH script
  ssh_keys_part = length(var.additional_ssh_keys) > 0 ? local.ssh_script : ""

  # The full user data script
  user_data = "${local.ssh_keys_part}${file("user_data.sh")}"
}

# Create EC2 instance
resource "aws_instance" "devops_workstation" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployment_key.key_name
  vpc_security_group_ids = [aws_security_group.devops_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_admin_profile.name
  user_data              = local.user_data

  tags = {
    Name = var.instance_name
  }

  # Wait for the instance to be fully initialized
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(pathexpand("~/.ssh/pin"))
    host        = self.public_ip
  }

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp2"
  }
}
