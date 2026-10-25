# 11. Proxmox as the hypervisor

Status: Accepted

## Context

- 3 small nodes: 2× Wyse 5070 with 8 GB and 1 custom box with 16 GB
- I want VMs + LXC, backups and remote management

- Alternatives:
  - Plain KVM / libvirt (why not: cluster, migration, web console and storage handling come out of the box instead of building them myself)
  - Gentoo with libvirt + QEMU (why not: the workload isn't static or special enough to justify tuning USE flags (Gentoo's main point), and compiling + maintaining a host OS on thin clients is time taken from the services)
  - OpenShift (why not: it's Kubernetes, same reasons as [0012](0012-no-kubernetes.md), and its minimum node specs are above what a Wyse box has)
  - VergeOS (why not: commercial, aimed at enterprise, not free for a homelab)
- Proxmox is KVM/QEMU underneath anyway, the question is who builds the layer on top

## Decision

- Proxmox VE on all 3 nodes, in one cluster
- Proxmox has the biggest homelab community: guides, forum answers, someone already hit the same bug
- The PVE REST API: not used much yet beyond OpenTofu, but it's there and I want to build on it
- Enforced by: OpenTofu's bpg/proxmox provider, every guest is built through the PVE API

## Consequences

- Easier: PBS plugs straight in for backups (with a scoped token that can only write)
- Easier: the bpg/proxmox OpenTofu provider builds every guest from code ([0001](0001-tofu-and-cloud-init-for-vms.md))
- Easier: the hosts are plain Debian, so the Ansible roles (firewall, AIDE, login-notify) work without special cases

- Accepted: tied to Proxmox's API and tooling. Moving away means rewriting `tofu/` and the PVE roles

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (OpenTofu), [0012](0012-no-kubernetes.md) (no Kubernetes)
