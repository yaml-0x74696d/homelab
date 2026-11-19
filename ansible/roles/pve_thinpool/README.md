# pve_thinpool

- Writes the fill of every LVM thin pool on the PVE nodes as node-exporter textfile metrics
- Gatus asks Prometheus for the highest value and alerts above `gatus_thinpool_max_pct`. A full thin pool stops its VMs, and nothing else warns before that

## Runs on

- proxmox (`playbooks/deploy-pve-thinpool.yml`)

## How it works

- `/usr/local/sbin/pve-thinpool-metrics` runs `lvs`, keeps the thin pools (attr `t…`) and writes `thinpool_data_metric` and `thinpool_metadata_metric` per pool (labels `vg`, `pool`) to a temp file, then moves it over `thinpool.prom`
- `pve-thinpool-metrics.timer` runs it every `pve_thinpool_interval`
- A drop-in on `prometheus-node-exporter.service` adds `--collector.textfile.directory`, on top of the `ARGS` from `/etc/default`. The role stops if Debian's defaults file isn't there
- Prometheus' `pve-hosts` job scrapes the metrics with the rest
- Gatus (`apps/gatus/config.yaml.j2`): two checks, `thin pool data` and `thin pool metadata`, each `max(<metric>)` against the limit. No result at all (the collector stopped) fails too. Gatus compares the value as an integer, so 85.9 passes a limit of 85

## Settings

| Variable | Default | What |
|---|---|---|
| `pve_thinpool_interval` | `5min` | Timer interval |
| `pve_thinpool_textfile_dir` | `/var/lib/prometheus/node-exporter` | node-exporter's textfile dir, AIDE leaves it out |
| `pve_thinpool_file` | `thinpool.prom` | File in that dir |
| `pve_thinpool_data_metric`, `pve_thinpool_metadata_metric` | `thinpool_*_metric` (group_vars) | Metric names, Gatus queries the same ones |
| `gatus_thinpool_max_pct`, `gatus_thinpool_interval` | group_vars | Limit and check interval, in `app_settings.yml` |

## Related

- [ADR 0027: Gatus](../../../docs/adr/0027-gatus-generated-from-apps-map.md)
