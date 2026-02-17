# Terraform (libvirt) Usage

This document describes the Terraform setup in this repo: what it manages, how to run it, and how to adjust it (e.g. GPU passthrough).

## Overview

- **Provider:** [dmacvicar/libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest) (version 0.7.1).
- **Connection:** `qemu:///system` (local libvirt on the same host where you run Terraform).
- **Resources:**
  - One base volume (Ubuntu Noble cloud image).
  - Two VMs: **k8s-core** and **k8s-inference**, each with a cloned disk and cloud-init.

## What Gets Created

| Resource   | Purpose |
|-----------|---------|
| `libvirt_volume.ubuntu_base` | Ubuntu Noble cloud image (downloaded once, used as base). |
| `libvirt_volume.k8s_core_disk` | 20GB disk for k8s-core (clone of base). |
| `libvirt_volume.k8s_inference_disk` | 50GB disk for k8s-inference (clone of base). |
| `libvirt_cloudinit_disk.commoninit` | Cloud-init ISO: `ansible` user, SSH key from `~/.ssh/id_rsa.pub`, sudo NOPASSWD. |
| `libvirt_domain.k8s_core` | VM: 4GB RAM, 2 vCPU, default NAT network. |
| `libvirt_domain.k8s_inference` | VM: 16GB RAM, 4 vCPU, optional PCI GPU passthrough. |

## Running Terraform

From the **repo root**:

```bash
cd terraform
terraform init    # once (or after adding/changing providers)
terraform plan   # show planned changes
terraform apply  # create or update resources
```

To destroy all created VMs and volumes:

```bash
terraform destroy
```

## Outputs

After a successful apply, Terraform outputs the VM IPs (from the default libvirt NAT network):

- **core_ip** – IP of the k8s-core VM.
- **inference_ip** – IP of the k8s-inference VM.

Use these for Ansible inventories or SSH, e.g.:

```bash
ssh ansible@$(terraform output -raw core_ip)
```

## Cloud-init and SSH Key

The cloud-init config in `main.tf` uses:

```hcl
file("~/.ssh/id_rsa.pub")
```

That path is resolved on the **machine where you run Terraform** (your Ubuntu server). The user that runs `terraform apply` must have `~/.ssh/id_rsa.pub`. If you use another key, change the path in the `libvirt_cloudinit_disk.commoninit` block.

## GPU Passthrough (k8s-inference)

The **dmacvicar/libvirt** provider does **not** support `hostdev` (PCI passthrough) in the `libvirt_domain` resource. The k8s-inference VM is created without a GPU; add passthrough **after** `terraform apply`:

1. **Discover the GPU BDF** on the host:
   ```bash
   virsh nodedev-list --tree
   # or
   lspci | grep -i vga
   ```
   Example: `0000:01:00.0` (optionally `0000:01:00.1` for audio).

2. **Create a hostdev XML file** (e.g. `gpu-hostdev.xml`):
   ```xml
   <hostdev mode='subsystem' type='pci' managed='yes'>
     <source>
       <address domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
     </source>
   </hostdev>
   ```

3. **Attach the device** (VM must be shut down for many GPUs):
   ```bash
   virsh shutdown k8s-inference
   virsh attach-device k8s-inference gpu-hostdev.xml --config
   virsh start k8s-inference
   ```

Alternatively, run `virsh edit k8s-inference` and add the `<hostdev>...</hostdev>` block under `<devices>`. Changes made via `virsh edit` are **not** managed by Terraform; re-applying may overwrite them if the provider later supports hostdev or you switch to a different workflow.

## Storage Pool

The config uses the **default** libvirt storage pool. Ensure it exists:

```bash
virsh pool-list
virsh pool-info default
```

If `default` is not active, create/start it (or change the `pool` argument in the `libvirt_volume` resources to your pool name).

## Network

Both VMs use `network_name = "default"` (usually `virbr0`, NAT). They get DHCP leases; Terraform waits for an address when `wait_for_lease = true`. To use a different network, change `network_name` in each `network_interface` block.

## Troubleshooting

### Provider / init errors

- Run `terraform init -upgrade` if the provider version or lock file is wrong.
- Ensure the host has internet access so the provider can be downloaded.

### “Permission denied” (libvirt)

- Run Terraform as a user in the `libvirt` group and re-login after adding the group. See [ubuntu-server-setup.md](ubuntu-server-setup.md).

### “Could not find PCI device”

- If you attached a GPU via `virsh attach-device` or `virsh edit`, the GPU BDF in your hostdev XML must match this host. Use `lspci` / `virsh nodedev-list --tree` to get the correct address and update the XML, or detach the device if you do not need GPU passthrough.

### Base image download fails

- Check the `source` URL in `libvirt_volume.ubuntu_base` (no trailing spaces).
- Ensure the host can reach `https://cloud-images.ubuntu.com`.

### Cloud-init not applied / cannot SSH

- Confirm `~/.ssh/id_rsa.pub` exists on the host for the user running Terraform.
- Wait a minute after first boot for cloud-init to run; then try `ssh ansible@<core_ip>`.
