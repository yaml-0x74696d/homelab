# chrony

- Time sync with chrony
- Only authenticated sources (NTS), so nobody on the path can feed a wrong time

## Runs on

- The VMs (`docker_hosts`), in `playbooks/base.yml`
- Not the LXCs (they use the host's clock) and not the pve nodes (PVE ships its own chrony)

## How it works

1. Installs `chrony`
2. Renders `/etc/chrony/chrony.conf` with one `server … iburst nts` line per server
3. Enables and starts chrony
4. Restarts chrony when the config changes

## Settings

Set in `group_vars/all/base.yml`, shared with `nixos/base`.

| Variable | Default | What |
|---|---|---|
| `chrony_servers` | PTB ×3 + Cloudflare | NTS servers (the Debian pool has no NTS) |
| `chrony_makestep_threshold` | 1 | Seconds of offset that get stepped instead of slewed |
| `chrony_makestep_limit` | 3 | For how many updates after start stepping is allowed |

## Notes

- NTS needs outbound tcp/4460 for the key exchange, then udp/123
- Check with `chronyc -N authdata` (NTS column) and `chronyc tracking`
