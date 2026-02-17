# Ubuntu Server Setup for Terraform (libvirt)

This guide documents how to prepare a fresh Ubuntu server so you can run the Terraform in this repo and create the KVM/libvirt VMs. You can either run the **bootstrap script** (recommended) or follow the **manual steps**.

## Prerequisites

- Ubuntu 22.04 or 24.04 (or compatible)
- Sudo access
- Network access (for APT and Terraform provider download)
- This repo cloned or copied to the server (e.g. under `~/home-lab-iac`)

---

## Option 1: Automated (bootstrap script)

From the **repo root** on the server:

```bash
cd /path/to/home-lab-iac
chmod +x scripts/bootstrap-ubuntu.sh
./scripts/bootstrap-ubuntu.sh
```

The script will:

1. Install Terraform from the HashiCorp APT repository
2. Install `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `bridge-utils`
3. Enable and start the `libvirtd` service
4. Add the current user to the `libvirt` group
5. Run `terraform init` in the `terraform/` directory

**After the script finishes:**

1. **Re-login** (or run `newgrp libvirt`) so the `libvirt` group is applied. Otherwise `qemu:///system` may fail with permission denied.
2. Ensure `~/.ssh/id_rsa.pub` exists (Terraform’s cloud-init config references it).
3. Apply Terraform:

   ```bash
   cd /path/to/home-lab-iac/terraform
   terraform plan
   terraform apply
   ```

---

## Option 2: Manual steps

### 1. Install Terraform

Add the HashiCorp APT repository and install Terraform:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install -y terraform
```

Verify:

```bash
terraform version
```

### 2. Install libvirt and KVM

The Terraform config uses the libvirt provider with `qemu:///system`, so the host must run libvirt and QEMU/KVM:

```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
```

Optional (for `virsh` and development):

```bash
sudo apt install -y virtinst libvirt-dev
```

### 3. Start and enable libvirt

```bash
sudo systemctl enable --now libvirtd
```

Check:

```bash
sudo systemctl status libvirtd
```

### 4. Add your user to the libvirt group

Required so you can use `qemu:///system` without root:

```bash
sudo usermod -aG libvirt "$USER"
```

**Log out and log back in** (or run `newgrp libvirt`) so the new group is active.

### 5. SSH key for cloud-init

The Terraform cloud-init config injects `~/.ssh/id_rsa.pub` into the VMs. On the server, ensure that file exists for the user who runs Terraform:

```bash
ls -la ~/.ssh/id_rsa.pub
```

If you use a different key, edit the `libvirt_cloudinit_disk` block in `terraform/main.tf` and change the path.

### 6. Run Terraform

From the repo root:

```bash
cd /path/to/home-lab-iac/terraform
terraform init
terraform plan
terraform apply
```

Confirm with `yes` when prompted (or use `terraform apply -auto-approve` if appropriate).

---

## Quick reference

| Step              | Command / action |
|-------------------|------------------|
| Install Terraform | HashiCorp APT repo (see above) |
| Install libvirt   | `sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients` |
| Enable libvirt    | `sudo systemctl enable --now libvirtd` |
| Permissions       | `sudo usermod -aG libvirt $USER` then **re-login** |
| Terraform         | `cd terraform && terraform init && terraform plan && terraform apply` |

---

## Troubleshooting

### “Permission denied” connecting to libvirt

- Ensure you re-logged in (or ran `newgrp libvirt`) after adding your user to `libvirt`.
- Check: `groups` should list `libvirt`.

### “Could not open '/var/run/libvirt/libvirt-sock'”

- libvirtd may not be running: `sudo systemctl start libvirtd`.
- User not in `libvirt` group: run `sudo usermod -aG libvirt $USER` and re-login.

### Cloud-init / SSH key file not found

- Terraform resolves `file("~/.ssh/id_rsa.pub")` on the machine where you run Terraform. Create the key on the server if needed: `ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa` (or point the config to your key path).

### Optional: genisoimage for cloud-init

If you see errors about `genisoimage` or `mkisofs`:

```bash
sudo apt install -y genisoimage
```

---

## Next steps

- See [terraform.md](terraform.md) for Terraform details, GPU passthrough, and outputs.
- Use the Terraform outputs `core_ip` and `inference_ip` for Ansible or SSH.
