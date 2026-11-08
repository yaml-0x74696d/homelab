# reach

- Checks every host of the play is up before a long run starts
- Hosts in `reach_optional_hosts` may be off: they're skipped and named in the summary, the run goes on
- Any other host that's down fails loudly, the plays after it leave it out

## Runs on

- First play of `playbooks/update.yml` and `playbooks/aide.yml`, on the same hosts as the plays after it
- `-l <host>` works as usual: only the limited hosts get checked

## How it works

1. `wait_for_connection` for up to `reach_timeout` seconds. Also tests the login, and sudo where the group uses it. Runs in `--check` too
2. Up: the host joins the group `reachable`. The plays after it target `<group>:&reachable`
3. Down and in `reach_optional_hosts`: joins `reach_skipped`, the task counts as rescued, so the run still exits 0
4. Down and not in the list: joins `reach_down` and fails. The run goes on with the others and exits non-zero at the end

## Settings

| Variable | Default | What |
|---|---|---|
| `reach_timeout` | 30 | Seconds of retries before a host counts as down |
| `reach_optional_hosts` | `[]`, set in group_vars `hosts.yml` | Hosts that may be off: `part_time_nodes` and their guests from `guest_nodes` (`network.yml`, tofu places the guests from the same map) |

## Notes

- The group names `reachable`, `reach_skipped` and `reach_down` are fixed: playbook host patterns can't read role variables
- `roles/update`'s summary reads `reach_skipped` and `reach_down`
- Without this play, a `serial: 1` batch whose only host is down ends the whole playbook, so nothing after it runs
- A host that goes down after this check still fails as unreachable
- haos sits on pve-3 too, but Ansible never logs in there (`appliances`)
