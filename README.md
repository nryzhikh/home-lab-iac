# Home Lab IaC

Terraform and automation for a home lab: KVM/libvirt VMs (Ubuntu Noble), including a Kubernetes core node and an inference node with optional GPU passthrough.

## What This Repo Does

- **Terraform** (libvirt provider): Provisions two VMs on a single Ubuntu host:
  - **k8s-core**: 4GB RAM, 2 vCPU, 20GB disk
  - **k8s-inference**: 16GB RAM, 4 vCPU, 50GB disk, optional GPU passthrough
- Both VMs use Ubuntu Noble cloud images and a shared cloud-init (SSH key, `ansible` user).
- Outputs VM IPs for use with Ansible or other tooling.

## Prerequisites

- **Ubuntu server** (22.04 or 24.04 recommended) where Terraform will run and VMs will live
- **sudo** and network access on that server
- **SSH key**: pass your public key when running Terraform (see below)

## Quick Start (Automated)

On a **fresh Ubuntu server** where this repo is cloned (or copied):

```bash
cd /path/to/home-lab-iac
./scripts/bootstrap-ubuntu.sh
```

The script will:

1. Install Terraform (HashiCorp APT repo)
2. Install and enable libvirt/KVM
3. Add your user to the `libvirt` group
4. Run `terraform init` in `terraform/`

**After it finishes:** log out and back in (or run `newgrp libvirt`) so the `libvirt` group takes effect, then:

```bash
cd /path/to/home-lab-iac/terraform
# Provide your SSH public key (used by cloud-init for the ansible user)
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_rsa.pub)"
terraform plan    # review changes
terraform apply   # create/update VMs
```

See [docs/ubuntu-server-setup.md](docs/ubuntu-server-setup.md) for full manual steps and troubleshooting.

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/ubuntu-server-setup.md](docs/ubuntu-server-setup.md) | Prepare Ubuntu: install Terraform, libvirt/KVM, permissions |
| [docs/terraform.md](docs/terraform.md) | Terraform usage, GPU passthrough, outputs, troubleshooting |

## Project Layout

```
.
├── README.md
├── docs/
│   ├── ubuntu-server-setup.md
│   └── terraform.md
├── scripts/
│   └── bootstrap-ubuntu.sh
└── terraform/
    └── main.tf
```

## Optional: cloud-init dependency

If you use cloud-init with `genisoimage` for generating ISO images, install it on the host:

```bash
sudo apt install -y genisoimage
```

(Some setups use `mkisofs` from `genisoimage`.)
