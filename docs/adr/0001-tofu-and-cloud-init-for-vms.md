# 1. OpenTofu and cloud-init for VMs

Status: Accepted

## Context

- The VMs were clicked together by hand, so a rebuild was never the same twice
- Guests: the three Docker VMs, the NetBird VM, the storage LXC and the log LXC, spread over 3 Proxmox nodes
- Turning on 2FA for `root@pam` broke password login for any automation

- Alternatives:
  - Proxmox clones (why not: more space usage on pve-hosts, less fitting for IaC)
  - Terraform (why not: not open source anymore)
  - Keep clicking (why not: not IaC)

## Decision

Tools:
- OpenTofu `>= 1.6` with the `bpg/proxmox ~> 0.66` provider (`tofu/providers.tf`)
- cloud-init in create mode: each node imports the Debian 13 genericcloud image itself (`proxmox_download_file`, needs the `import` content type on `local`)
- cloud-init sets the static IP, gateway, DNS, admin user and SSH key
- Ansible takes over from there

Where the settings live:
- All guest specs are in two maps in `tofu/locals.tf`: `vms` and `lxcs` (VMID, node, cores, memory, balloon floor, disk, IP, MACs)
- IPs, VMIDs, the admin user, the SSH key path and the pool paths come from `ansible/group_vars/all/` through `yamldecode` ([0007](0007-group-vars-single-source-of-truth.md))

Login to Proxmox:
- OpenTofu uses an API token for `root@pam` that is exempt from 2FA (`pveum user token add root@pam terraform --privsep 0`)
- A password is kept as a fallback, empty by default, because tokens can't set bind mounts on an LXC (needed for the storage CT)
- The provider also logs in over SSH (agent, root) to import disks and upload files

Guest details:
- The storage LXC comes from the `debian-13-standard` template: unprivileged, nesting on, the pool bind-mounted
- Disks use `virtio-scsi-single` with iothread
- `discard = "on"` and `ssd = true` let the guest's trim free blocks in the thin pool
- Ballooning: each VM has a floor (`floating`) below its full RAM (`dedicated`)
- The floors are set at or above measured usage, because the VMs have no disk swap (the NetBird VM only has zram)
- The LXCs have no ballooning, they get a small `swap` instead
- MACs are fixed and follow the VMID (`BC:24:11:…`), which pins the DHCP leases
- NixOS finds the NetBird VM's network card by that MAC

- Enforced by: `tofu plan` shows any drift, and anything changed by hand is reverted on the next apply

## Consequences

- Easier: a rebuild is `tofu apply` + `vm-preparation.yml` + the deploy playbooks
- Easier: guest specs are in one reviewed map instead of the PVE UI

- Harder: the bootstrap order matters:
  1. mergerfs pool (`deploy-storage.yml --limit pve-3`)
  2. `tofu apply`
  3. `vm-preparation.yml`
  4. Samba
  5. `site.yml`
- Harder: qemu-guest-agent is installed by Ansible, so `agent { enabled = true }` needs a second apply
- Harder: recreating the storage CT needs `pve_password` and 2FA turned off for that one run

- Accepted: the image is downloaded once per node, because `local` is not shared storage
- Accepted: settings changed by hand get reverted unless they are declared (e.g. discard/ssd, without them the thin pool fills up)
- Accepted: a `--privsep 0` token has full control of the cluster. It only lives in the git-ignored `terraform.tfvars` and can be revoked

- Stateful VMs are protected with `prevent_destroy` ([0005](0005-prevent-destroy-on-stateful-vms.md))
- The NetBird VM is only a Debian shell here, nixos-anywhere replaces the OS afterwards ([0008](0008-nixos-for-the-dmz-box.md))

- Related: [0005](0005-prevent-destroy-on-stateful-vms.md) (prevent_destroy), [0007](0007-group-vars-single-source-of-truth.md) (shared vars), [0008](0008-nixos-for-the-dmz-box.md) (NixOS on the NetBird VM), [0011](0011-proxmox-as-hypervisor.md) (Proxmox), [0025](0025-debian-guests-until-x86-64-v3.md) (guest OS)
