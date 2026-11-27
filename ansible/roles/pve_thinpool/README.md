# pve_thinpool

- Writes the fill of every LVM thin pool on the PVE nodes as node-exporter textfile metrics
- Gatus asks Prometheus per node and alerts above `gatus_thinpool_max_pct` or when the file goes stale. A full thin pool stops its VMs, and nothing else warns before that

## Runs on

- proxmox (`playbooks/deploy-pve-thinpool.yml`)

## How it works

1. `/usr/local/sbin/pve-thinpool-metrics` runs `lvs`, keeps the thin pools (attr `t…`) and writes `pve_thinpool_data_percent` and `pve_thinpool_metadata_percent` (`thinpool_*_metric`) per pool (labels `vg`, `pool`) to a temp file, then moves it over `thinpool.prom`
2. `pve-thinpool-metrics.timer` runs it every `pve_thinpool_interval`
3. A drop-in on `prometheus-node-exporter.service` adds `--collector.textfile.directory`, on top of the `ARGS` from `/etc/default`. The role stops if Debian's defaults file isn't there
4. Prometheus' `pve-hosts` job scrapes the metrics with the rest
5. Gatus (`apps/gatus/config.yaml.j2`): per node `<node> thin pool data`, `<node> thin pool metadata` and `<node> thin pool metrics fresh`, queried with `instance="<ip>:<node_exporter_port>"` (the `pve-hosts` job's label). The fresh check is `time() - node_textfile_mtime_seconds` of the file against `gatus_thinpool_stale_max`. No result at all fails every check. Gatus compares values as integers, so 85.9 passes a limit of 85

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `pve_thinpool_interval` | `{{ thinpool_interval_min }}min` | How often the timer runs (systemd time span), `thinpool_interval_min` minutes (5) |
| `pve_thinpool_textfile_dir` | `/var/lib/prometheus/node-exporter` | node-exporter's textfile collector dir, AIDE leaves it out |
| `pve_thinpool_file` | `thinpool_file` | File name in that dir (`thinpool.prom`), the fresh check matches it |
| `pve_thinpool_data_metric` | `thinpool_data_metric` | Metric name of a pool's data percent, Gatus queries the same one |
| `pve_thinpool_metadata_metric` | `thinpool_metadata_metric` | Metric name of a pool's metadata percent, Gatus queries the same one |
<!-- settings:end -->

Also from group_vars (app_settings.yml): `gatus_thinpool_max_pct` (limit per node), `gatus_thinpool_stale_max` (seconds before the file counts as stale, 3 x the interval), `gatus_thinpool_interval` (check interval).

## Related

- [ADR 0027: Gatus](../../../docs/adr/0027-gatus-generated-from-apps-map.md)
