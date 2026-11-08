# NixOS layout

Where things are kept in `nixos/`, where the values come from, and how the NetBird VM is changed.

## Where does it go

| To change | File |
|---|---|
| an IP, a port, a domain, a MAC | `ansible/group_vars/all/` (read through `facts.nix`) |
| time, logging (same as the Debian guests) | `ansible/group_vars/all/base.yml`, used in `base/` |
| hostname, boot, network | `netbird/configuration.nix` |
| disk layout | `netbird/disko.nix` |
| the NetBird server, nginx, OIDC | `netbird/netbird.nix` |
| firewall, SSH, sysctls, fail2ban, auto-upgrade | `netbird/hardening.nix` |
| AIDE rules | `netbird/aide.nix` |
| nixpkgs, disko versions | `flake.lock` (`nix flake update`) |

## Folders

```
nixos/
├── flake.nix         inputs (nixpkgs, disko, private), the netbird system
├── flake.lock        pinned input versions
├── facts.nix         group_vars YAML → one attrset (facts)
├── base/             modules every NixOS host would share: time, logging
├── netbird/          one host: configuration.nix imports the rest
├── update.sh         bump, build, switch, check
└── aide-accept.sh    review and accept AIDE changes
```

- One folder per host, shared modules in `base/`
- Gitignored: `result*` (build output)

## Where the values come from

- `facts.nix` turns `network`, `ports`, `hosts`, `app_settings`, `apps`, `base` and `private.yml` into JSON with yq-go at build time
- Modules get them as `facts` (through `specialArgs`): `facts.netbird_ip`, `facts.domain`
- `private` is a flake input. It defaults to the repo's `private/` folder, the example is used when `private.yml` is missing (CI). Real builds point it at the real folder: `--override-input private path:<dir>`, `update.sh` does this
- Same files as Ansible and OpenTofu ([ADR 0007](adr/0007-group-vars-single-source-of-truth.md))

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
nixos/update.sh                       # bump inputs, build, switch, check failed units
nixos/aide-accept.sh                  # after an intended change
cd nixos && nix flake check           # what pre-commit and CI run
```

- `update.sh` builds first, so a renamed option fails before anything is switched
- Rollback: `ssh root@<netbird> nixos-rebuild switch --rollback`
- The VM was installed once with nixos-anywhere, OpenTofu only made the empty VM ([ADR 0008](adr/0008-nixos-for-the-dmz-box.md))

## Conventions

- No value from group_vars is typed again in a module, it's read from `facts`
- A module that isn't tied to one host goes in `base/`
- `system.stateVersion` stays at the first install's release
- `nix flake check` needs builds (facts.nix runs yq), `--no-build` can't work
