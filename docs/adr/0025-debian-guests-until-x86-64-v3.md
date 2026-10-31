# 25. Debian 13 for the guests until the CPUs have x86-64-v3

Status: Accepted

## Context

- The guests are docker-1/2/3 (the pod hosts after the Podman migration) and the storage, log and IoT LXCs
- EL10 (RHEL 10, Rocky 10) needs x86-64-v3 (AVX2). The CPUs here are x86-64-v2, and the guests run `cpu type = host`
- I want the EL world (SELinux, dnf) on the guests eventually

- Alternatives:
  - AlmaLinux 10, x86-64-v2 build (why not: a side build with fewer users, errata timing for v2 unverified, the base roles need an EL branch, the PBS client only exists as a static binary)
  - EL9: RHEL 9, Alma 9 or Rocky 9 (why not: full support ends 2027-05-31, and there's no way on to EL10 with these CPUs)
  - Debian 13 (chosen)
- Why: no repo work now, and EL10 proper once the hardware allows it, instead of a side build or an EL9 dead end

## Decision

- The guests stay on Debian 13, the Podman migration ([0021](0021-podman-quadlets.md)) included
- EL10 is revisited when the hardware has x86-64-v3
- The PVE nodes stay Debian ([0011](0011-proxmox-as-hypervisor.md)), the NetBird VM stays NixOS ([0008](0008-nixos-for-the-dmz-box.md))

- Enforced by: `debian_image_url` and `lxc_template` in `tofu/variables.tf`, the image and template every guest is built from ([0001](0001-tofu-and-cloud-init-for-vms.md))

## Consequences

- Easier: the roles stay as they are, one OS family on every Ansible host
- Easier: the PBS client comes as a native package

- Harder: Debian 13 security support ends 2028-08-09 (LTS until 2030-06-30), so the guests need the Debian 14 upgrade before that

- Accepted: Podman runs under AppArmor, not SELinux
- Accepted: no EL on the guests for now

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (images), [0008](0008-nixos-for-the-dmz-box.md) (NetBird VM), [0011](0011-proxmox-as-hypervisor.md) (PVE on Debian), [0021](0021-podman-quadlets.md) (pod hosts), [0024](0024-ansible-run-os-updates.md) (apt updates), [0026](0026-ufw-as-guest-firewall.md) (no firewalld)
