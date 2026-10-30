# 7. group_vars as the single source of truth

Status: Accepted

## Context

- Three tools describe the same lab: Ansible (config + apps), OpenTofu (VMs/LXC) and NixOS (NetBird VM)
- IPs, VMIDs, ports, MACs and schedules were copied between them and drifted apart
- After DNS moved to the `.53` service IP, an OpenTofu resolver setting still pointed at the old Pi-hole host `.201`. It silently fell through to the gateway
- Before the change, the same values were copied all over the repo:

  | Value | Copies |
  |---|---|
  | LAN CIDR | 7 |
  | NetBird IP | 5 |
  | Gateway | 4 |
  | Domain | ~30 |
  | NetBird MAC | OpenTofu + Nix |
  | Relay port range | PVE firewall + Nix |
  | AIDE schedule | Ansible + Nix |

- Alternatives:
  - OpenTofu outputs → Ansible inventory (why not: only exists after `tofu apply`, Nix can't read it)
  - A separate facts file all three read (why not: Ansible would need lookups instead of native group_vars, one more file for no gain)
  - NetBox / an IPAM (why not: another service to run, overkill for ~10 IPs)
  - Keep copies (why not: they drifted)

## Decision

The source:
- `ansible/group_vars/all/` holds the facts, split by topic: `network.yml`, `ports.yml`, `storage.yml`, `hosts.yml`, `apps.yml`
- `vault.yml` holds the secrets and is only read by Ansible
- Shared schedules and timeouts live there too (`aide_check_time`, `ntfy_timeout`, SSH settings), so the Ansible hosts and the Nix box behave the same

How each tool reads it:
- Ansible: as normal group_vars, the inventory's `ansible_host` points at the `*_ip` variables
- OpenTofu: `tofu/locals.tf` reads network/ports/hosts/storage with `yamldecode(file(...))`, and the VM specs (`vms`/`lxcs` maps) are built on top
- Nix: `nixos/facts.nix` turns network/ports/hosts/apps into JSON with yq-go at build time (import from derivation). Every module gets the result as `specialArgs.facts`
- Shell: `nixos/update.sh` and `aide-accept.sh` read `netbird_ip` with `nix run nixpkgs#yq-go`

- Enforced by: `just check` runs `tofu validate` and `nix flake check` against the same files, so a missing or renamed variable fails

## Consequences

- Easier: an IP, port or schedule is changed once, and tofu plan, the Nix build and Ansible all pick it up

- Harder: YAML that OpenTofu or Nix reads must stay plain. Jinja values (`mqtt_broker_ip: "{{ docker1_ip }}"`, the allow lists in `ports.yml`) only work in Ansible
- Harder: `nix flake check --no-build` can't work, because facts.nix needs a build
- Harder: flakes only see files tracked by git, so a new vars file has to be added to git first

- Accepted: the NixOS flake reaches outside its own folder (`../ansible`), so it only works from a full checkout of the repo
- Accepted: it's one big shared namespace. Role-specific settings still go in `roles/<role>/defaults`, only facts used by more than one tool belong here

- Related: [0001](0001-tofu-and-cloud-init-for-vms.md), [0008](0008-nixos-for-the-dmz-box.md)
