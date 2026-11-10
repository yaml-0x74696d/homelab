# 14. Authentik as the identity provider

Status: Accepted

## Context

- Without SSO every web app has its own login, plus the NetBird VPN
- Some apps speak OIDC: Gitea, Nextcloud, Immich, Paperless, Vaultwarden, Grafana, Jellyfin, NetBird
- Some have no login at all: Traefik dashboard, Prometheus
- I'm the only admin, and I want MFA everywhere without setting it up per app

- Alternatives:
  - Authelia (why not: fewer features, no admin UI)
  - Keycloak (why not: heavy (Java), built for enterprise)
  - Per-app logins (keep as is) (why not: no MFA everywhere, many passwords)
- Why: OIDC + forward-auth in one, web UI, MFA built in

## Decision

The setup:
- Authentik on pod-1 (`apps/authentik`, `deploy-authentik.yml`): one Podman pod with server, worker and Postgres (`16-alpine`, no auto-update)
- MFA is enforced in Authentik
- Every app keeps a local admin as a break-glass account, except Vaultwarden (`SSO_ONLY=true`)
- The version is pinned as the image tag in `group_vars/all/apps.yml`, the release series it may step through are `authentik_series` in `app_settings.yml`

Two ways apps use it:
- OIDC, for apps that support it
  - The app hands the login to Authentik but keeps its own sessions and API
  - So mobile apps, sync clients and git clients keep working
  - NetBird logs in this way too (public PKCE client, [0003](0003-netbird-instead-of-port-forwards.md))
- Forward-auth, for UIs that are only used in the browser
  - Traefik middleware `authentik` on edge (`nixos/edge/traefik.nix`) sends the request to the embedded outpost on pod-1 first
  - Used by the Traefik dashboard, Prometheus and the Vaultwarden admin page

Connecting apps:
- Containers can't resolve internal names, so apps reach `auth.<domain>` through an `AddHost=` entry pointing at edge ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- Each app's client ID and secret is entered once, through its CLI or as a Podman secret from the vault

- Enforced by: `deploy-authentik.yml` wraps the `podman_app` role; its pre-tasks refuse downgrades against the running image, skipped release series, and pulls while pve-1's thin pool is above `authentik_pool_max_pct` (85 %)

## Consequences

- Easier: one login with MFA for every app and the VPN
- Easier: apps without a login get one, without touching the app (forward-auth)

- Harder: upgrades go one release series at a time (raise the tag in `apps.yml`, deploy, repeat). Database migrations can take a while, the start may take up to `start_timeout` in `apps.yml`
- Harder: OIDC is set up by hand for every app (provider + application in Authentik, client in the app)

- Accepted: Authentik is a single point of failure for logins. That's why every app except Vaultwarden keeps a local break-glass admin, and monitoring isn't fully behind it
- Accepted: with Authentik down, Vaultwarden takes no new logins. Clients that are already logged in keep their offline copy

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird OIDC), [0015](0015-tls-via-dns-01.md) (TLS), [0002](0002-generic-docker-app-role.md) (app role)
