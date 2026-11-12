# 34. TLS only via DNS-01, no port 80 from the WAN

Status: Accepted

## Context

- Every app is LAN / VPN only, but should still get a trusted certificate under `<domain>`
- HTTP-01 needs the name to be reachable from the internet on port 80
- The only WAN-facing guest is the NetBird VM, with 443 + TURN ([0003](0003-netbird-instead-of-port-forwards.md))
- Traefik moved from pod-1 to the edge VM ([0032](0032-edge-vm-traefik-adguard-on-nixos.md))
- [0015](0015-tls-via-dns-01.md) made the same choice, but still described Traefik on pod-1, one certificate per router and the `.env` of `proxy`

- Alternatives:
  - HTTP-01 with a port 80 forward (why not: port 80 open to the WAN)
  - An internal CA (why not: the CA has to be installed on every device)
  - Self-signed (why not: browser warnings everywhere)
- Why: real certificates without opening a port

## Decision

- Let's Encrypt everywhere, through ACME DNS-01 against Cloudflare

Traefik (edge, `nixos/edge/traefik.nix`):
- One wildcard certificate for `<domain>` and `*.<domain>`, shared by every router on 443
- Uses the certresolver `cloudflare` and stores the certificate in `acme.json` in Traefik's data dir
- The Cloudflare token sits in `/var/lib/secrets/edge/cloudflare.env`, never in git
- Before asking Let's Encrypt, Traefik checks that the record is visible on public resolvers (`acmeResolvers`). AdGuard Home answers the zone locally, so asking it would break the check
- Traefik's `:80` only redirects to `:443`

NetBird VM (`nixos/netbird/netbird.nix`):
- `security.acme` with `dnsProvider = "cloudflare"`, used by nginx through `useACMEHost`
- coturn reuses the same certificate for TURN over TLS (`turns:5349`)

Public DNS:
- cloudflare-ddns (Podman, one copy each on pod-1 and pod-2) keeps the public records pointed at the current WAN IP, with the same token

- Enforced by: the router forwards no port 80, and nftables on the NetBird VM only opens 443 + TURN

## Consequences

- Easier: real certificates for LAN-only names, and nothing on the WAN is needed to renew them
- Easier: one wildcard certificate instead of one per router, fewer Let's Encrypt orders
- Easier: certificates renew on their own, about 30 days before they expire. If `acme.json` gets lost, they're simply issued again

- Harder: the Cloudflare API token can edit DNS for the whole zone. It lives in the vault (`cf_token`), on edge, on the NetBird VM and as a Podman secret on pod-1 and pod-2 (cloudflare-ddns)
- Harder: renewals depend on Cloudflare's API and public DNS

- Accepted: whoever gets root on edge, the NetBird VM, pod-1 or pod-2 can edit the whole zone
- Accepted: a wildcard certificate covers every name under the domain, a stolen key would too
- Accepted: Traefik talks plain HTTP to the backends on the LAN
- Accepted: every certificate lands in the public certificate transparency logs, so the app hostnames are public (the apps themselves aren't)

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0010](0010-lan-dns-on-a-service-ip.md) (split-horizon DNS), [0014](0014-authentik-as-idp.md) (SSO), [0015](0015-tls-via-dns-01.md) (superseded), [0032](0032-edge-vm-traefik-adguard-on-nixos.md) (edge)
