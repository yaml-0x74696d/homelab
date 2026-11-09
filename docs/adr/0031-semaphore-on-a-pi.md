# 31. Semaphore on a Raspberry Pi as the always-on runner

Status: Accepted

## Context

- Every playbook ran by hand from ctl-0, my desktop, which is only on when I use it
- Updates, AIDE checks and deploys should also run on a schedule, with a run history
- I didn't want another VM in the cluster for it, and an unused Raspberry Pi 3 was lying around
- The Pi has 1 GB RAM, a 16 GB SD card and an ARM CPU, so the PBS client (amd64 only) doesn't run there

- Alternatives:
  - cron or systemd timers on ctl-0 (why not: ctl-0 is off most of the time)
  - AWX (why not: needs Kubernetes, see [0012](0012-no-kubernetes.md))
  - Rundeck (why not: a Java server, too heavy for 1 GB)
  - A VM in the cluster (why not: one more guest to run, and it goes down with the cluster it manages)
  - Semaphore on the Pi (chosen)
  - Keep running everything by hand (why not: nothing runs while ctl-0 is off)
  - Authentik forward-auth in front of the route (why not: Semaphore logs in through OIDC itself, a second login on top, and API tokens and webhooks can't follow the redirect)
- Why Semaphore: open source, one Go binary with SQLite, an ARM64 image, schedules and run history in a web UI

## Decision

The setup:
- ctl-1 (`ctl1_ip`) is the Pi on Raspberry Pi OS Lite, bare metal outside tofu, in the `podman_hosts` group
- `playbooks/ctl-preparation.yml` runs `vm_base`, `podman_base`, `roles/ctl_base` and `aide` on it
- Semaphore is a rootless Podman app (`apps/semaphore`, [0021](0021-podman-quadlets.md)) with SQLite, behind Traefik as `semaphore.<domain>`
- Login through Authentik OIDC ([0014](0014-authentik-as-idp.md)), plus a local `semaphore_admin_user` as break-glass
- The container runs on the host network: ansible has to reach ctl-1's own sshd, and pasta hands `ctl1_ip` back to the container

The code it runs:
- A git clone of the public repo on `semaphore_repo_version` (`podman-migration`, `main` once it is merged) at `semaphore_repo_dir`, mounted read-only into the container
- `playbooks/repo-pull.yml` pulls it, as a Semaphore template
- The quadlet sets `ANSIBLE_CONFIG`, `AIDE_CHECKSUM_DIR` and `HOMELAB_PRIVATE_DIR` and forwards them to the tasks (`SEMAPHORE_FORWARDED_ENV_VARS`), so templates need no variable group
- The gitignored `vault.yml` and `private.yml` come from ctl-0 (`ctl_base_private_files`, tag `private-files`)
- ctl-0's `<private_dir>/apps` (the private config overlays, nothing else from that dir) is mirrored with rsync to `semaphore_private_dir` in the same run and mounted read-only at that path. `HOMELAB_PRIVATE_DIR` points `podman_app` and `docker_app` at it, `private.yml`'s `~/...` would be the container user's home
- The vault password and Semaphore's ssh key live only in Semaphore's key store, encrypted with `semaphore_key_encryption`. No vault password and no tofu state on the Pi
- `ansible.cfg` needs a `.vault_pass`, so the clone gets a dummy one, the real password comes from the key store
- Semaphore's public key goes to every host through `push-keys.yml`

Schedules (set in the UI, Semaphore's own database):
- `repo-pull` daily 11:45, `aide` daily 13:15, `update` Saturday 14:00 with `--limit 'all:!ctl-1'` ([0024](0024-ansible-run-os-updates.md))
- Gatus reads each one's last run through the API (`gatus_semaphore_templates`, a guest-role user's token) and alerts when it failed

AIDE hashes:
- Semaphore keeps the accepted hashes in its own rw dir (`/srv/apps/semaphore/aide`, `AIDE_CHECKSUM_DIR`). That copy is the reference for every Debian host, ctl-1 included
- `aide-accept.yml` accepts in Semaphore through the survey var `aide_accept=yes`, the diff stays in the task log
- ctl-0's `ansible/aide` is a copy, pulled back with rsync after accepts. The NetBird VM's hash stays on ctl-0 (`nixos/aide-accept.sh`)

- Enforced by: the read-only repo and private dir mounts, ufw on ctl-1 (port from `allow_from` only, ssh from the LAN), and the hash compare in `roles/aide` before every run and accept

## Consequences

- Easier: updates and AIDE checks run on a schedule while ctl-0 is off, with a history per run
- Easier: everything runs from one git branch, the private files and `private_dir` come from one tagged run from ctl-0, nothing copied by hand

- Harder: a vault, `private.yml` or `private_dir` change needs a run from ctl-0 before Semaphore sees it
- Harder: ctl-1 holds the keys to every host, so it is the most valuable box to break into

- Accepted: ctl-1 holds the AIDE hashes for all hosts, itself included. Root on ctl-1 could swap a database and its hash together. ctl-0's copy is the cross-check, if I pull it after every accept
- Accepted: `aide_accept=yes` accepts what the run finds, without a second look before the swap
- Accepted: no backup of the Pi. Projects and templates are quick to redo, the run history is lost with the card
- Accepted: the SD card wears, so the journal is volatile and goes to the log LXC ([0022](0022-central-logging-relp.md))

- Related: [0009](0009-aide-with-manual-accept.md) (AIDE), [0012](0012-no-kubernetes.md), [0014](0014-authentik-as-idp.md), [0016](0016-ansible-vault-for-secrets.md) (vault), [0021](0021-podman-quadlets.md), [0022](0022-central-logging-relp.md), [0024](0024-ansible-run-os-updates.md) (updates), [0026](0026-ufw-as-guest-firewall.md), [0027](0027-gatus-generated-from-apps-map.md) (failed runs)
