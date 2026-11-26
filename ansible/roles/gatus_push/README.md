# gatus_push

- Tells Gatus a scheduled playbook went through, as the last play of `repo-pull.yml`, `aide.yml` and `update.yml`
- Gatus alerts when the heartbeat stays away longer than the job's window (`heartbeat_daily`, `heartbeat_weekly` in `schedules.yml`)
- A failed run isn't pushed. Semaphore's own status check ([ADR 0027](../../../docs/adr/0027-gatus-generated-from-apps-map.md)) covers failures, this covers runs that never happened

## Runs on

- Once per run, from the controller or Semaphore (ctl-1), delegated to the Gatus host (pod-2): the Gatus port only lets in the lab hosts
- The play has the same hosts as the playbook, without `:&reachable`. If any of them failed earlier, `ansible_play_hosts` is shorter than `ansible_play_hosts_all` and nothing is pushed
- Not in `--check`, not with `--limit` (a partial run would reset the heartbeat), not while `gatus_push_token` is empty or missing from the vault

## How it works

1. `POST http://localhost:<gatus port><gatus_push_path>` with the key `<gatus_push_group>_semaphore-<job>`, with `Authorization: Bearer <gatus_push_token>`
2. `apps/gatus/config.yaml.j2` generates the external endpoints from `gatus_semaphore_templates` (`app_settings.yml`), the job name has to match a name there
3. The task has `no_log`, the token is in the vault

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `gatus_push_path` | required | Push path with {key} for the endpoint key (group_vars) |
| `gatus_push_job` | required | Semaphore template name (`repo-pull`, `aide` or `update`), the external endpoint is semaphore-\<job> (gatus_semaphore_templates) |
| `gatus_push_group` | required | Gatus endpoint group of the heartbeats (group_vars) |
| `gatus_push_timeout` | required | Seconds the push may take (group_vars) |
| `gatus_push_token` | `""` | Gatus push token (vault), also in Semaphore's copy of the vault (`ctl-preparation.yml -l ctl-1 -t private-files`). empty = no push |
<!-- settings:end -->

## Related

- `pbs` role (same heartbeat for the backups)
- [ADR 0027: Gatus](../../../docs/adr/0027-gatus-generated-from-apps-map.md)
