resource "aws_key_pair" "deployment_key" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.ssh_key_path))

  lifecycle {
    ignore_changes = [public_key]
  }
}
