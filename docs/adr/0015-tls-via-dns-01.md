# 15. TLS only via DNS-01, no port 80 from the WAN

Status: Accepted

## Context

- Every app is LAN / VPN only, but should still get a trusted certificate under `<domain>`
- HTTP-01 needs the name to be reachable from the internet on port 80
- The only WAN-facing guest is the NetBird VM, with 443 + TURN ([0003](0003-netbird-instead-of-port-forwards.md))

- Alternatives:
  - HTTP-01 with a port 80 forward (why not: port 80 open to the WAN)
  - An internal CA (why not: the CA has to be installed on every device)
  - Self-signed (why not: browser warnings everywhere)
- Why: real certificates without opening a port

## Decision

- Let's Encrypt everywhere, through ACME DNS-01 against Cloudflare

Traefik (docker-1):
- Uses the certresolver `cloudflare` (`dnschallenge.provider=cloudflare`)
- Gets one certificate per router and stores them in `acme.json` (mode `0600`)
- The Cloudflare token `cf_token` comes from the vault
- Before asking Let's Encrypt, Traefik checks that the record is visible on public resolvers (`traefik_acme_resolvers: 1.1.1.1:53,8.8.8.8:53` in `deploy-proxy.yml`). Pi-hole answers the zone locally, so asking it would break the check
- Traefik's `:80` stays LAN-only and only redirects to `:443`

NetBird VM (`nixos/netbird/netbird.nix`):
- `security.acme` with `dnsProvider = "cloudflare"`, used by nginx through `useACMEHost`
- coturn reuses the same certificate for TURN over TLS (`turns:5349`)

Public DNS:
- cloudflare-ddns (`apps/utilities`) keeps the public records pointed at the current WAN IP, with the same token

- Enforced by: the FRITZ!Box forwards no port 80, and nftables on the NetBird VM only opens 443 + TURN

## Consequences

- Easier: real certificates for LAN-only names, and nothing on the WAN is needed to renew them
- Easier: certificates renew on their own, about 30 days before they expire. If `acme.json` gets lost, they're simply issued again

- Harder: the Cloudflare API token can edit DNS for the whole zone, it lives in the vault, on docker-1 (`.env` of `proxy` and `utilities`, mode `0600`) and on the NetBird VM
- Harder: renewals depend on Cloudflare's API and public DNS

- Accepted: whoever gets root on docker-1 or the NetBird VM can edit the whole zone
- Accepted: every certificate lands in the public certificate transparency logs, so the app hostnames are public (the apps themselves aren't)

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0010](0010-pihole-on-a-service-ip.md) (split-horizon DNS), [0014](0014-authentik-as-idp.md) (SSO)
