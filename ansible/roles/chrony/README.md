# chrony

- Time sync with chrony
- Only authenticated sources (NTS), so nobody on the path can feed a wrong time

## Runs on

- The VMs and ctl-1 (`pod_vms`, `podman_hosts`), in `playbooks/base.yml`
- Not the LXCs (they use the host's clock) and not the pve nodes (PVE ships its own chrony)

## How it works

1. Installs `chrony`
2. Renders `/etc/chrony/chrony.conf` with one `server … iburst nts` line per server
3. Enables and starts chrony
4. Restarts chrony when the config changes

## Settings

Set in `group_vars/all/base.yml`, shared with `nixos/base`.

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `chrony_servers` | - | NTS servers, set in group_vars/all/base.yml, default PTB x3 + Cloudflare (the Debian pool has no NTS) |
| `chrony_makestep_threshold` | - | Seconds of offset that get stepped instead of slewed, set in group_vars/all/base.yml, default 1 |
| `chrony_makestep_limit` | - | For how many updates after start stepping is allowed, set in group_vars/all/base.yml, default 3 |
<!-- settings:end -->

## Notes

- NTS needs outbound tcp/4460 for the key exchange, then udp/123
- Check with `chronyc -N authdata` (NTS column) and `chronyc tracking`

## Related

- [ADR 0023: chrony with NTS for time sync](../../../docs/adr/0023-chrony-with-nts.md)
