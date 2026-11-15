# 38. Linkding, Memos and Excalidraw on pod-3

Status: Accepted

## Context

- Bookmarks were a hand-written list in Homepage (`apps/homepage/config/bookmarks.yaml`), quick notes and sketches had no place in the lab
- All three should log in through Authentik like the other apps ([0014](0014-authentik-as-idp.md)) and keep their data in the lab
- Small is the goal: one container and SQLite where it works, so the backup is one more `pbs_jobs` line ([0013](0013-pbs-file-level-backups.md))
- pod-2 is tight on RAM since Actual Budget ([0037](0037-actual-budget-on-pod-2.md)), pod-3 has the room

- Alternatives:
  - Karakeep for bookmarks (why not: three containers with headless Chrome and Meilisearch, AGPL)
  - Linkwarden for bookmarks (why not: Postgres and Meilisearch next to the app, AGPL)
  - Docmost for notes (why not: OIDC login is an Enterprise feature, Postgres and Redis)
  - An own Excalidraw build without the excalidraw.com backends (why not: one more image to build and keep current)
  - Keep the bookmark list in Homepage (why not: no search, no tags, one deploy per link)
  - Linkding, Memos and the official Excalidraw image (chosen)
- Why: each one is a single container, linkding and Memos store in SQLite, and linkding is MIT licensed

## Decision

The setup:
- All three run as rootless Podman apps on pod-3 (`apps/linkding`, `apps/memos`, `apps/excalidraw`, [0021](0021-podman-quadlets.md)), served by Traefik as `links.<domain>`, `memos.<domain>` and `draw.<domain>`
- Tiles in Homepage's Tools group, uptime checks in Gatus, both from `apps.yml`

Login:
- linkding: OIDC through Authentik only, `LD_DISABLE_LOGIN_FORM=True`. Users match by `preferred_username`, the client secret is a Podman secret (`linkding_oidc_secret`)
- Memos: the SSO provider is set in Memos' admin UI and lives in its database. The first account is a local admin, it stays as the break-glass login
- Excalidraw has no accounts. The route sits behind the `authentik` forward-auth middleware

Excalidraw stays local:
- The image is built with excalidraw.com's share, collaboration and library servers in its config (`.env.production` upstream)
- The route adds the `local-only` middleware (`nixos/edge/traefik.nix`): a Content-Security-Policy with `connect-src 'self'`, so the browser refuses every call outside the app's own origin
- A drawing lives in the browser's storage, export goes to a file

Data:
- linkding `data/db.sqlite3` and Memos `data/memos_prod.db` are dumped by `pbs_jobs` entries on pod-3, the rest of their data dirs goes with the file-level archive
- Excalidraw keeps nothing on the server

- Enforced by: `LD_DISABLE_LOGIN_FORM` in `apps/linkding/linkding.container.j2`, the middlewares on the `draw` route in `apps.yml` (the edge build fails on an undefined one), `allow_from` on each app

## Consequences

- Easier: bookmarks are searchable and tagged, and added from the browser instead of a deploy
- Easier: three more apps through the same pattern, no new runtime and no new database server

- Harder: a new linkding user is an Authentik account with the same username, there is no local login to fall back on
- Harder: the CSP has to match what Excalidraw loads. A new upstream feature that loads from outside shows up as a blocked request in the browser console

- Accepted: Excalidraw's share links, live collaboration and the public library browser don't work
- Accepted: an Excalidraw drawing is only as safe as the browser's storage, a cleared browser loses what wasn't exported
- Accepted: all three follow `latest` or `stable`, like the other apps

- Related: [0013](0013-pbs-file-level-backups.md) (backups), [0014](0014-authentik-as-idp.md) (SSO), [0021](0021-podman-quadlets.md) (Podman apps), [0037](0037-actual-budget-on-pod-2.md) (pod-2's RAM)
