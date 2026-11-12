# 33. No Kubernetes

Status: Accepted

## Context

- K8s or k3s would be a good learning experience
- The workload is static: fixed apps on fixed hosts, no autoscaling, no rolling deploys at scale
- The 8 GB nodes run at ~7.5 GB used, about 0.5 GB stays free
- A k3s server needs 2 GB RAM at minimum (k3s docs, hardware requirements)
- The apps run as Podman quadlets, one host per app ([0021](0021-podman-quadlets.md))
- The lab has to stay usable day to day
- [0012](0012-no-kubernetes.md) said the same, but its reason ("doesn't fit in 8 GB") was vague and its decision still described compose stacks

- Alternatives:
  - K8s (why not: the control plane needs more RAM than is free, features unused)
  - k3s (why not: 2 GB server minimum against ~0.5 GB free, features unused)
  - OpenShift (why not: see [0011](0011-proxmox-as-hypervisor.md), node specs too high)
  - Plain quadlets, one host per app (chosen)

## Decision

- No Kubernetes, no k3s
- Apps run as Podman quadlets ([0021](0021-podman-quadlets.md))
- Placement is set by hand per app (`host:` in `apps.yml`), not by a scheduler
- Enforced by: nothing to enforce. Revisit when the hardware changes

## Consequences

- Easier: simpler to debug, one host and a few unit files per app

- Harder: none of K8s's features (scheduling, self-healing, scaling) would get used, but its overhead would (control plane RAM, etcd, networking layer)

- Accepted: a dead node means its apps are down until they're restored from PBS. There's no automatic failover

- Later: k3s on a rented server (Hetzner) as a learning cluster outside the lab

- Related: [0011](0011-proxmox-as-hypervisor.md) (OpenShift), [0012](0012-no-kubernetes.md) (superseded), [0021](0021-podman-quadlets.md) (quadlets)
