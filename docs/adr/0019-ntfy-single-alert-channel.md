# 19. ntfy.sh as the single alert channel

Status: Accepted

## Context

- Several things need to reach my phone: failed backups, AIDE changes, logins on the PVE hosts, new images
- Alerts must also work when I'm away, while nothing in the lab is reachable from the internet
- A self-hosted ntfy stays LAN-only, but instant push on the iPhone needs a server that's reachable from the internet (Apple's push service, APNs)

- Alternatives:
  - Self-hosted ntfy exposed to the WAN (why not: one more service open to the internet)
  - Mail (why not: needs a mail server or account, no instant push)
  - A chat bot (why not: depends on a chat platform and its API)
  - Uptime Kuma notifications only (why not: only knows up/down, not backups or AIDE)
- Why: instant push on the phone, nothing inbound, a simple curl from any script

## Decision

The channel:
- One ntfy.sh topic, outbound only: lab → ntfy.sh → phone app
- Shared variables in `group_vars/all/apps.yml`: `ntfy_url` (includes the topic), `ntfy_token` (optional), `ntfy_timeout` (10 s)
- The real values are in the vault
- On the free tier, the topic name is the secret, so it's long and random

Who sends:

| Sender | What |
|---|---|
| `roles/pbs` | A failed run or an empty dump |
| `roles/aide` | Changes on `<host>`, counts only, or "aide failed" |
| `roles/login_notify` | SSH and PVE web logins on the Proxmox hosts |
| `apps/diun` | New image digests (endpoint and topic are split from `ntfy_url` in `.env.j2`) |
| NetBird VM | AIDE results, through `/var/lib/secrets/aide/ntfy.env` |

How sending works:
- Every sender uses `curl -m ntfy_timeout … || true`, so a failed push never fails the job
- If `ntfy_url` is empty, the senders still run but stay quiet

- Enforced by: one set of variables that every sender reads, no targets per role

## Consequences

- Easier: one place to change the target, one app on the phone
- Easier: nothing inbound, nothing exposed

- Harder: the alert text goes through a public relay. That's why AIDE only sends counts, and the changed paths stay in the host's journal

- Accepted: login-notify pushes the full journal line (user, source IP) through that relay
- Accepted: it depends on ntfy.sh being up, and a lost push isn't retried
- Accepted: anyone who finds out the topic name can read and post to it

- Related: [0009](0009-aide-with-manual-accept.md) (AIDE, counts only), [0013](0013-pbs-file-level-backups.md) (PBS alerts), [0006](0006-latest-images-notify-only.md) (Diun)
