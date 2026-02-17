#!/usr/bin/env bash
# Bootstrap Ubuntu server for home-lab-iac Terraform (libvirt).
# Run from repo root: ./scripts/bootstrap-ubuntu.sh
# See docs/ubuntu-server-setup.md for full documentation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

# --- 1. Terraform (HashiCorp APT) ---
if ! command -v terraform &>/dev/null; then
  echo "Installing Terraform..."
  wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt update
  sudo apt install -y terraform
  echo "Terraform installed: $(terraform version)"
else
  echo "Terraform already installed: $(terraform version)"
fi

# --- 2. libvirt / KVM ---
echo "Ensuring libvirt and KVM are installed..."
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils

echo "Enabling and starting libvirtd..."
sudo systemctl enable --now libvirtd

# --- 3. User in libvirt group ---
if ! groups "$USER" | grep -q libvirt; then
  echo "Adding $USER to group libvirt..."
  sudo usermod -aG libvirt "$USER"
  echo "NOTE: Log out and back in (or run: newgrp libvirt) for the libvirt group to take effect."
else
  echo "User $USER is already in group libvirt."
fi

# --- 4. Terraform init ---
if [[ ! -d "$TERRAFORM_DIR" ]]; then
  echo "ERROR: Terraform directory not found: $TERRAFORM_DIR" >&2
  exit 1
fi

echo "Running terraform init in $TERRAFORM_DIR..."
cd "$TERRAFORM_DIR"
terraform init

echo ""
echo "Bootstrap done. Next steps:"
echo "  1. Log out and back in (or run: newgrp libvirt)"
echo "  2. cd $TERRAFORM_DIR"
echo "  3. terraform plan && terraform apply"
echo "See docs/ubuntu-server-setup.md and docs/terraform.md for more."
