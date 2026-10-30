# 8. NixOS for the NetBird VM only

Status: Accepted

## Context

- The NetBird control plane is the only VM that takes inbound WAN traffic (443/tcp, 3478/udp and a small TURN relay range). The FRITZ!Box WireGuard is the only other way in
- It sits on pve-2 as an isolated DMZ VM
- Its only data is the NetBird SQLite store, so it's cheap to rebuild
- Everything else runs Debian + Ansible

- Alternatives:
  - Debian + Ansible like the rest (why not: not fully declared, no easy rollback)
  - NetBird in Docker on a Docker host (why not: no real DMZ)
- Why NixOS only here: small, stateless VM, good place to learn NixOS

## Decision

The setup:
- A NixOS flake in `nixos/` (`nixosConfigurations.netbird`)
- nixpkgs unstable, for the `services.netbird.server` module
- disko describes the disk layout
- NetBird runs natively, no Docker: management, signal and dashboard from the nixpkgs module, coturn for STUN/TURN, nginx with ACME DNS-01 (Cloudflare, no port 80)

Install and updates:
- OpenTofu creates the VM shell on the Debian cloud image
- nixos-anywhere then wipes it and installs the flake (legacy-BIOS GPT + ext4)
- Day-to-day updates run `nixos/update.sh` from the controller:
  1. Update the flake inputs
  2. `build` first, which catches renamed options
  3. `switch --target-host`
  4. Check for failed units
  5. Warn if a new kernel needs a reboot
- `system.autoUpgrade` also runs nightly between 04:00 and 04:45 (random delay) from the git repo, reboots are only allowed between 03:00 and 05:00

Hardening (`netbird/hardening.nix`):
- Users only come from the config (immutable users), SSH is key-only, LAN-only and on port `ssh_port`, with modern ciphers/KEX/MACs only
- nftables denies by default, only 443 and the coturn ports are public
- On 443 the WAN only reaches the gRPC paths
- The dashboard (`/`) and `/api` only answer the LAN (nginx `geo` on `lan_cidr`), everyone else gets `return 444`, a silent close
- VPN peers count as LAN, because their traffic is NATed through the routing peer
- The fail2ban jail `nginx-lan-only` bans after 5 hits on those paths in 10 minutes (`probeMaxRetry` / `probeFindTime` in `netbird.nix`)
- Kernel parameters and sysctls (`slab_nomerge`, `init_on_free`, `kptr_restrict=2`, `kexec_load_disabled` and more)
- AppArmor, auditd, and fail2ban for SSH (3 tries, 1 hour ban)
- AIDE watches the few paths an upgrade never touches ([0009](0009-aide-with-manual-accept.md))

Secrets:
- Put on the VM by hand under `/var/lib/secrets/` (datastore key, TURN secret, Cloudflare token), never in git

- Enforced by: the whole OS is the flake, `update.sh` builds before it switches, and `just check` runs `nix flake check`

## Consequences

- Easier: the whole OS is in git, a rollback is just the previous generation (`nixos-rebuild switch --rollback`)

- Harder: a second deploy path next to Ansible, with Nix tooling on the controller and its own update script
- Harder: the unstable channel has the newest NetBird module, but upgrades can break options. That's why update.sh builds before it switches
- Harder: autoUpgrade builds `main` of the public GitHub repo with its local copy of `private.yml` (`/etc/homelab-private`), so a change on `testing` only sticks once it's merged, and a `private.yml` change needs an `update.sh` run

- Accepted: the management service only has the module's own sandbox. Extra systemd sandboxing kills netbird-mgmt during the OIDC call
- Accepted: the secrets live outside Nix for now, agenix/sops is still open

- Facts are shared with the rest through group_vars ([0007](0007-group-vars-single-source-of-truth.md))

- Related: [0003](0003-netbird-instead-of-port-forwards.md) (NetBird), [0007](0007-group-vars-single-source-of-truth.md) (shared vars), [0009](0009-aide-with-manual-accept.md) (AIDE), [0022](0022-central-logging-relp.md) (logging), [0023](0023-chrony-with-nts.md) (time)
