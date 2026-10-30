# 12. No Kubernetes

Status: Accepted

## Context

- K8s or k3s would be a good learning experience
- The workload is static: fixed apps on fixed hosts, no autoscaling, no rolling deploys at scale
- RAM is already tight
- The 8 GB thin clients run at ~7.5 GB used
- A move from compose to Podman quadlets is planned ([0021](0021-podman-quadlets.md), proposed)
- The lab has to stay usable day to day

- Alternatives:
  - K8s (why not: control plane doesn't fit in 8 GB, features unused)
  - k3s (why not: control plane doesn't fit in 8 GB, features unused)
  - OpenShift (why not: see [0011](0011-proxmox-as-hypervisor.md), node specs too high)
  - Keep compose / quadlets (chosen)

## Decision

- No Kubernetes, no k3s
- Apps run as compose stacks on the Docker VMs ([0002](0002-generic-docker-app-role.md))
- They move to Podman quadlets later, see the plan in the README ([0021](0021-podman-quadlets.md))
- Placement is set by hand per app (`hosts:` in `deploy-<app>.yml`), not by a scheduler
- Enforced by: nothing to enforce. Revisit when the hardware changes

## Consequences

- Easier: simpler to debug, one host and one compose file per app

- Harder: none of K8s's features (scheduling, self-healing, scaling) would get used, but its overhead would (control plane RAM, etcd, networking layer)
- Harder: there's no room on the 8 GB nodes for a control plane next to the apps

- Accepted: a dead node means its apps are down until they're restored from PBS. There's no automatic failover

- K8s stays a learning topic outside the lab

- Related: [0002](0002-generic-docker-app-role.md) (app role), [0011](0011-proxmox-as-hypervisor.md) (OpenShift), [0021](0021-podman-quadlets.md) (quadlets)
