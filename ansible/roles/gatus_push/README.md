# gatus_push

- Tells Gatus a scheduled playbook went through, as the last play of `repo-pull.yml`, `aide.yml` and `update.yml`
- Gatus alerts when the heartbeat stays away longer than the job's window (`heartbeat_daily`, `heartbeat_weekly` in `schedules.yml`)
- A failed run isn't pushed. Semaphore's own status check ([ADR 0027](../../../docs/adr/0027-gatus-generated-from-apps-map.md)) covers failures, this covers runs that never happened

## Runs on

- Once per run, from the controller or Semaphore (ctl-1), delegated to the Gatus host (pod-2): the Gatus port only lets in the lab hosts
- The play has the same hosts as the playbook, without `:&reachable`. If any of them failed earlier, `ansible_play_hosts` is shorter than `ansible_play_hosts_all` and nothing is pushed
- Not in `--check`, not with `--limit` (a partial run would reset the heartbeat), not while `gatus_push_token` is empty or missing from the vault

## How it works

- `POST http://localhost:<gatus port><gatus_push_path>` with the key `<gatus_push_group>_semaphore-<job>`, with `Authorization: Bearer <gatus_push_token>`
- The external endpoints are generated from `gatus_semaphore_templates` in `apps/gatus/config.yaml.j2`, the job name has to match the template name there
- The task has `no_log`, the token is in the vault

## Settings

| Variable | Default | What |
|---|---|---|
| `gatus_push_job` | required | Template name: `repo-pull`, `aide` or `update` |
| `gatus_push_group`, `gatus_push_path`, `gatus_push_timeout` | group_vars | Endpoint group, push path (`{key}` is the endpoint key), seconds the push may take |
| `gatus_push_token` | vault | Push token, also in Semaphore's copy of the vault (`ctl-preparation.yml -l ctl-1 -t private-files`) |

## Related

- `pbs` role (same heartbeat for the backups)
- [ADR 0027: Gatus](../../../docs/adr/0027-gatus-generated-from-apps-map.md)
