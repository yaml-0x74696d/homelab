# 23. chrony with NTS for time sync

Status: Accepted

## Context

- The VMs synced time with `systemd-timesyncd` from the Debian pool, over plain NTP
- Plain NTP isn't authenticated: anyone on the path can feed a wrong time
- A wrong clock breaks TLS certificates, TOTP logins (Authentik, Vaultwarden) and the order of log lines across hosts

- Alternatives:
  - Keep timesyncd (why not: no NTS, only one source at a time)
  - chrony from the Debian pool (why not: the pool has no NTS)
  - FRITZ!Box as LAN time server (why not: plain NTP, one source, mediocre accuracy)
  - pve-3 as LAN time server for the guests (why not: one more thing to run, and it would still need a trusted upstream)
- Why: chrony with NTS gives authenticated time from several independent sources with no extra service

## Decision

- chrony on every VM (`roles/chrony`, `playbooks/base.yml`, NetBird VM: `nixos/base/time.nix`), sources only with `iburst nts`
- Servers (`chrony_servers` in `group_vars/all/base.yml`): `ptbtime1/2/3.ptb.de` (PTB, stratum 1) and `time.cloudflare.com`
- `makestep 1 3` steps the clock on the first updates after boot or a VM resume, `rtcsync` keeps the RTC in step
- The NetBird VM keeps the module's `rtcautotrim`, the Debian VMs use `rtcsync`
- LXCs use the host's clock, the PVE nodes keep their own chrony
- NTS needs outbound tcp/4460 for the key exchange, then udp/123

- Enforced by: `chronyc -N authdata` shows `NTS` for every source

## Consequences

- Easier: a spoofed time source is rejected, not trusted
- Easier: four sources, chrony picks the best and drops outliers

- Harder: depends on a short, fixed server list instead of the pool

- Accepted: if all four servers are unreachable, the clock free-runs until they're back

- Related: [0008](0008-nixos-for-the-dmz-box.md) (NetBird VM), [0022](0022-central-logging-relp.md) (log timestamps across hosts), [0014](0014-authentik-as-idp.md) (TOTP)
