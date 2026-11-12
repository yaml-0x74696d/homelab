# NixOS layout

Where things are kept in `nixos/`, where the values come from, and how the two NixOS VMs (netbird, edge) are changed.

## Where does it go

| To change | File |
|---|---|
| an IP, a port, a domain, a MAC | `ansible/group_vars/all/` (read through `facts.nix`) |
| time, logging (same as the Debian guests) | `ansible/group_vars/all/base.yml`, used in `base/` |
| hostname, boot, network, upgrade time + reboot window | `<host>/configuration.nix` |
| disk layout | `base/disko.nix` |
| the NetBird server, nginx, OIDC | `netbird/netbird.nix` |
| a Traefik route | `ansible/group_vars/all/apps.yml` (`routes:` of the app, or `infra_routes:`), then rebuild edge |
| Traefik middlewares, entrypoints, the wildcard cert | `edge/traefik.nix` |
| AdGuard Home: upstreams, blocklist, query log | `edge/adguard.nix` |
| firewall, SSH, sysctls, fail2ban, auto-upgrade | `base/hardening.nix` (service ports in the host's modules) |
| AIDE rules | `base/aide.nix` |
| nixpkgs, disko versions | `flake.lock` (`nix flake update`) |

## Folders

```
nixos/
├── flake.nix         inputs (nixpkgs, disko, private), one nixosConfiguration per host folder
├── flake.lock        pinned input versions
├── facts.nix         group_vars YAML → one attrset (facts), plus host_ips from the inventory
├── base/             modules every NixOS host shares: time, logging, hardening, AIDE, disk layout, fastfetch
├── netbird/          NetBird control plane: configuration.nix imports the rest
├── edge/             Traefik + AdGuard Home: configuration.nix imports the rest
├── update.sh         bump, build, switch, check (one host per run)
└── aide-accept.sh    review and accept AIDE changes (one host per run)
```

- One folder per host, shared modules in `base/`
- Gitignored: `result*` (build output)

## Where the values come from

- `facts.nix` turns `network`, `ports`, `hosts`, `app_settings`, `apps`, `base` and `private.yml` into JSON with yq-go at build time
- Modules get them as `facts` (through `specialArgs`): `facts.netbird_ip`, `facts.domain`
- `private` is a flake input. It defaults to the repo's `private/` folder, the example is used when `private.yml` is missing (CI). Real builds point it at the real folder: `--override-input private path:<dir>`, `update.sh` does this
- `facts.host_ips` maps every inventory host to its IP: `ansible_host` is `{{ <var> }}`, the var is looked up in the facts. edge uses it to turn an app's `host:` into a backend address
- Same files as Ansible and OpenTofu ([ADR 0007](adr/0007-group-vars-single-source-of-truth.md))

## How edge builds its routes

- Every `apps.<name>.routes` entry becomes a router and a service: `Host(<host>.<domain>)` (+ `PathPrefix` with `path`), backend `http://<host ip>:<route port or app port>`, the route's `middlewares`
- Every `infra_routes` entry with a `target` does too: `scheme://<target ip>:<ports.yml[port_var]>`, `insecure_tls` skips the backend's cert check. `target: edge` means something on edge itself (the Traefik dashboard, the AdGuard UI)
- Entries without a `target` are only served by pod-1's Traefik until the cutover
- AdGuard Home gets a rewrite to `edge_ip` for the same hosts
- A middleware name that `traefik.nix` doesn't define fails the build
- The result is `/etc/traefik/dynamic.yml`, a copied file Traefik watches, so a route change doesn't restart Traefik

## Which value is used

When two modules set the same option:

| Priority | Set with | |
|---|---|---|
| 1500 | `lib.mkOptionDefault` | option defaults of a module |
| 1000 | `lib.mkDefault` | a default meant to be overridden |
| 100 | plain `option = value;` | what this repo writes |
| 50 | `lib.mkForce` | wins over everything |

- The lower number wins. Two plain values that differ are an error, not a silent pick
- Lists and attrsets are merged across modules instead (`imports` add up)

## Deploy

```
nixos/update.sh <netbird|edge>        # bump inputs, build, switch, check failed units
nixos/aide-accept.sh <netbird|edge>   # after an intended change
cd nixos && nix flake check           # what pre-commit and CI run
```

- `update.sh` builds first, so a renamed option fails before anything is switched
- Rollback: `ssh root@<host> nixos-rebuild switch --rollback`
- Each VM is installed once with nixos-anywhere, OpenTofu only makes the empty VM ([ADR 0035](adr/0035-nixos-for-netbird-and-edge.md), [ADR 0032](adr/0032-edge-vm-traefik-adguard-on-nixos.md))
- Secrets go on the box by hand before the first switch: `/var/lib/secrets/netbird/`, `/var/lib/secrets/edge/cloudflare.env`, `/var/lib/secrets/aide/ntfy.env`
- autoUpgrade: netbird 03:00 to 04:00, edge 04:00 to 04:45, never both at once (`group_vars/all/schedules.yml`)

## Conventions

- No value from group_vars is typed again in a module, it's read from `facts`
- A module that isn't tied to one host goes in `base/`
- `system.stateVersion` stays at the first install's release
- `nix flake check` needs builds (facts.nix runs yq), `--no-build` can't work
