# 40. Grafana dashboards as code, provisioned by Ansible

Status: Accepted

## Context

- Grafana's dashboards were made in the UI and lived only in `grafana.db`: a rebuilt pod-2 would have lost them, and a change left no diff
- Only the Prometheus datasource was provisioned, with the uid of the click-made one
- Gatus and the thin pool check already feed Prometheus and the status page, but nothing showed them as graphs
- Four views are enough: the hosts, the PVE nodes with their thin pools, the sensors, and the health of the lab itself

- Alternatives:
  - Community dashboards from grafana.com (why not: hundreds of panels nobody reads, a diff nobody can review)
  - Keep clicking and export the JSON now and then (why not: the export drifts from what runs, same problem as before)
  - Grafonnet or another dashboard generator (why not: one more tool for four small files)
  - Own small JSON files, provisioned (chosen)
- Why: the files are few, readable in a diff, and use the same config mirror as every other app file

## Decision

The setup:
- `apps/grafana/config/provisioning/dashboards/` holds the provider (`dashboards.yaml`, folder `lab`) and four dashboards with fixed uids: `lab-hosts`, `lab-pve`, `lab-iot`, `lab-health`
- The mount is one more `Volume=` in `grafana.container.j2`, the files come through the config mirror of `roles/podman_app`
- Dashboards use the datasource by its fixed uid from `datasources/prometheus.yaml.j2`
- A dashboard that needs a dial is a `.json.j2`: the thin pool threshold is `gatus_thinpool_max_pct`, the metric names are `thinpool_data_metric` and `thinpool_metadata_metric`, the heartbeat group is `gatus_push_group`
- Gatus has `metrics: true` and Prometheus scrapes it (job `gatus`), for the lab health dashboard
- `allowUiUpdates` is on, so a dashboard can be tinkered with in the UI. The next deploy resets it to git, a keeper is saved as JSON in the repo
- `disableDeletion` is on: a file removed from git leaves its dashboard in Grafana until it is deleted there
- Dashboards made in the UI stay as they are, next to the folder `lab`

- Enforced by: the files are mirrored by `roles/podman_app` and Grafana reads them at start and every provider update interval

## Consequences

- Easier: a rebuilt Grafana comes back with its dashboards, a change is a reviewed diff
- Easier: a changed alert level moves the dashboards' thresholds with it

- Harder: a dashboard is edited as JSON, or built in the UI and exported into the repo
- Harder: the hosts dashboard labels hosts by their `instance` (ip and port), the scrape config has no host names

- Accepted: UI edits to the four dashboards are lost on the next deploy
- Accepted: the dashboards read Prometheus' 15 days, nothing longer

- Related: [0019](0019-ntfy-single-alert-channel.md) (alerts stay in ntfy, dashboards don't alert), [0021](0021-podman-quadlets.md) (config mirror), [0027](0027-gatus-generated-from-apps-map.md) (gatus metrics, thin pool), [0028](0028-iot-gateway-lxc.md) (sensor metrics)
