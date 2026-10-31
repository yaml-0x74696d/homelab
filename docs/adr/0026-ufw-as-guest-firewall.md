# 26. ufw as the guest firewall, also for Podman

Status: Accepted

## Context

- The Debian guests already run ufw (`vm-preparation.yml`, `roles/samba`)
- Rootless Podman publishes ports as plain host sockets, so the host firewall has to open each app's port
- The Podman plan had picked firewalld for the Podman VMs

- Alternatives:
  - firewalld (why not: Debian's cloud-init has `Conflicts: firewalld`, Debian bug #1025618, because the two services' systemd units form boot ordering cycles. Installing firewalld removes cloud-init)
  - plain nftables (why not: a third firewall style in the repo, rules written by hand)
  - ufw (chosen)

## Decision

- ufw stays the firewall on every Debian guest, the Podman VMs included
- `roles/podman_app` writes one rule per port and `allow_from` source of the app

- Enforced by: the ufw tasks in `vm-preparation.yml` and `roles/podman_app`

## Consequences

- Easier: one firewall tool on all guests, no switch at the rebuild, cloud-init stays
- Easier: Podman's ports need no `DOCKER-USER` workaround ([0018](0018-docker-user-port-filtering.md)), ufw sees them directly

- Harder: per-app owner-match rules (one app may not reach another app's port on the same VM) would have to go into ufw's `before.rules`

- Accepted: no firewalld on the guests while they run Debian ([0025](0025-debian-guests-until-x86-64-v3.md))

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md) (cloud-init), [0018](0018-docker-user-port-filtering.md) (Docker's ports), [0021](0021-podman-quadlets.md) (Podman), [0025](0025-debian-guests-until-x86-64-v3.md) (Debian)
