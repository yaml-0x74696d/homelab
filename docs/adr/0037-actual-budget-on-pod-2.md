# 37. Actual Budget on pod-2, login only through Authentik

Status: Accepted

## Context

- I want one place for the household budget: envelope budgeting, on the phone too, with the data in the lab
- After the passwords, bank data is the most private data here
- pod-2 has the room for one more small container, about 1.4 GiB were available when this was planned

- Alternatives:
  - Firefly III (why not: PHP plus a database of its own, more to run and back up than one SQLite container)
  - A spreadsheet (why not: no envelope budgeting, no phone, nothing shared)
  - A hosted app like YNAB (why not: the bank data leaves the lab, and a subscription)
  - Keep nothing (why not: no overview of the money at all)
  - Actual Budget (chosen)
- Why: local-first, one small container with SQLite, and a budget can be encrypted before it reaches the server

## Decision

The setup:
- Actual Budget runs as a rootless Podman app on pod-2 (`apps/actual`, [0021](0021-podman-quadlets.md)), port 5006, served as `actual.<domain>` by Traefik
- Image `ghcr.io/actualbudget/actual`, tag `latest`, auto-updated like the other apps
- Its state is `/srv/apps/actual/data`: `server-files/account.sqlite` (users, sessions, the list of budgets) and `user-files` (the budgets)

Login:
- OpenID Connect through Authentik ([0014](0014-authentik-as-idp.md)), set with environment variables only. The server sets itself up from them at every start
- It is the only login: `ACTUAL_LOGIN_METHOD` and `ACTUAL_ALLOWED_LOGIN_METHODS` are `openid`, `ACTUAL_OPENID_ENFORCE` is on. No password, no header login, no local admin
- The client secret is a Podman secret mounted as a file (`ACTUAL_OPENID_CLIENT_SECRET_FILE`), not an environment variable
- Users are created by hand in Actual, with the name they have in Authentik. The first OpenID login becomes the server owner
- A session lasts as long as Authentik's access token (`ACTUAL_TOKEN_EXPIRATION=openid-provider`)

Data:
- End-to-end encryption is turned on per budget, in the app. The server then only holds ciphertext, the password is kept in Vaultwarden
- No bank sync, statements are imported as files
- Backup: `account.sqlite` is dumped by a `pbs_jobs` entry on pod-2, `user-files` goes with the file-level archive ([0013](0013-pbs-file-level-backups.md))

- Enforced by: the login variables in `apps/actual/actual.container.j2`, and `allow_from` in `apps.yml` (only edge, pod-2 and Homepage reach the port)

## Consequences

- Easier: the budget is on every device and works offline, the server only syncs
- Easier: one entry in `apps.yml`, and the route, the DNS rewrite, the uptime check and the tile follow

- Harder: a new user is two steps, an account in Authentik and a user with the same name in Actual
- Harder: the end-to-end password can't be reset. Losing it together with every local copy loses the budget

- Accepted: with Authentik down nobody logs in or syncs, and there is no local login to fall back on (like Vaultwarden). A device that already has the budget keeps working on its copy
- Accepted: each budget's sync log (`user-files/group-<id>.sqlite`) is copied while the app runs, not dumped. Its name isn't known before the budget exists, and every device holds the whole budget and can reset sync
- Accepted: the image follows `latest`

- Related: [0013](0013-pbs-file-level-backups.md) (backups), [0014](0014-authentik-as-idp.md) (SSO), [0021](0021-podman-quadlets.md) (Podman apps), [0038](0038-linkding-memos-excalidraw-on-pod-3.md) (more apps, pod-3)
