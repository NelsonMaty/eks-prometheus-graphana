#!/bin/bash

# Set SSH directory and key name
SSH_DIR="$HOME/.ssh"
KEY_NAME="pin"
KEY_PATH="$SSH_DIR/$KEY_NAME"

# Ensure SSH directory exists
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Generate SSH key pair if it doesn't exist
if [ ! -f "$KEY_PATH" ]; then
  echo "Generating SSH key pair in $SSH_DIR..."
  ssh-keygen -t rsa -b 2048 -f "$KEY_PATH" -N ""
  chmod 400 "$KEY_PATH"
  echo "SSH key pair generated:"
  echo "  - Private key: $KEY_PATH"
  echo "  - Public key: $KEY_PATH.pub"
else
  echo "SSH key pair already exists at $KEY_PATH"
fi

# Display the path to the public key for Terraform to use
echo ""
echo "Public key path to use in Terraform: $KEY_PATH.pub"
echo "You can set this path in your terraform.tfvars file or specify it when running terraform apply:"
echo "terraform apply -var=\"ssh_key_path=$KEY_PATH.pub\""
