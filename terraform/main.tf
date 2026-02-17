terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init (ansible user). Set via TF_VAR_ssh_public_key or -var."
  type        = string
}

# 1. The Base Image (Download Ubuntu Cloud Image)
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-noble-base"
  pool   = "default" # Use your default storage pool
  source = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  format = "qcow2"
}

# 2. The Core Node (Master)
resource "libvirt_volume" "k8s_core_disk" {
  name           = "k8s-core.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 20 * 1024 * 1024 * 1024 # 20GB
}

# Cloud-Init Config for Core
resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  user_data = <<EOF
#cloud-config
users:
  - name: ansible
    ssh_authorized_keys:
      - ${var.ssh_public_key}
    sudo: ALL=(ALL) NOPASSWD:ALL
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
     ansible:password
  expire: False
EOF
}

resource "libvirt_domain" "k8s_core" {
  name   = "k8s-core"
  memory = "4096"
  vcpu   = 2

  network_interface {
    network_name = "default" # Usually virbr0 (NAT)
    wait_for_lease = true # Terraform waits until it gets an IP
  }

  disk {
    volume_id = libvirt_volume.k8s_core_disk.id
  }

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

# 3. The Inference Node (Worker with GPU)
resource "libvirt_volume" "k8s_inference_disk" {
  name           = "k8s-inference.qcow2"
  base_volume_id = libvirt_volume.ubuntu_base.id
  pool           = "default"
  size           = 50 * 1024 * 1024 * 1024 # 50GB
}

resource "libvirt_domain" "k8s_inference" {
  name   = "k8s-inference"
  memory = "16384"
  vcpu   = 4

  network_interface {
    network_name = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.k8s_inference_disk.id
    scsi      = "true"
  }

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # GPU/PCI passthrough: terraform-provider-libvirt does not support hostdev in HCL.
  # After apply, add the device manually, e.g.:
  #   virsh attach-device k8s-inference /path/to/gpu-hostdev.xml
  # Or edit: virsh edit k8s-inference and add a <hostdev> block under <devices>.
  # See docs/terraform.md for PCI address discovery (lspci / virsh nodedev-list).

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

# Output the IPs so Ansible knows where to go
output "core_ip" {
  value = libvirt_domain.k8s_core.network_interface.0.addresses.0
}

output "inference_ip" {
  value = libvirt_domain.k8s_inference.network_interface.0.addresses.0
}