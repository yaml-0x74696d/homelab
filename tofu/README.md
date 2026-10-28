# tofu

- OpenTofu builds the Docker VMs, the NetBird VM, the storage LXC and the log LXC with the `bpg/proxmox` provider
- The guests are created from a Debian cloud image, cloud-init sets the IP, the admin user and the SSH key
- IPs, VMIDs, the admin user, the SSH key path and the pool paths come from `../ansible/group_vars/all/` (read in `locals.tf`), so OpenTofu and Ansible can't drift apart
- Guest sizes, nodes and MACs are in the `vms` / `lxcs` maps in `locals.tf`

## 1. Login and storage

- The provider logs in with an API token for `root@pam` that is exempt from 2FA
- One exception: API tokens can't set bind mounts, so creating the storage LXC needs `pve_password`, with 2FA turned off for that run
- Turn on the **import** content type on the `local` datastore, it's needed for the cloud image (Datacenter → Storage → local → Content → Import)
- Run `ssh-add` with your root key, the provider also uses SSH (for the disk import)

## 2. tfvars

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
```

- Set `pve_api_token` and `vm_password` (the same as `sudo_pass` in the vault)

## 3. LXC template (once, on pve-3)

```bash
pveam update && pveam download local debian-13-standard
```

- If the file name differs from the default, change `lxc_template`

## 4. Apply

The storage CT bind-mounts the pool, so the pool has to exist first:

```bash
cd ../ansible && ansible-playbook playbooks/deploy-storage.yml --limit pve-3
cd ../tofu
tofu init
tofu apply
```

- The Docker VMs and the NetBird VM have `prevent_destroy`, because their databases live on the VM disk
- Never apply a plan that replaces one of them

## 5. After the first apply

- Once `vm-preparation.yml` has installed qemu-guest-agent, set `agent { enabled = true }` in `vms.tf` and run `tofu apply` again

## Related

- [ADR 0001: OpenTofu and cloud-init for VMs](../docs/adr/0001-tofu-and-cloud-init-for-vms.md)
- [ADR 0005: prevent_destroy on stateful VMs](../docs/adr/0005-prevent-destroy-on-stateful-vms.md)
