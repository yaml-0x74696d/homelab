# mqtt_exporter

- Turns the sensors' MQTT topics into Prometheus metrics
- Debian's `prometheus-mqtt-exporter` (upstream: mqtt2prometheus), next to the broker on the IoT gateway LXC

## Runs on

- The IoT gateway LXC (CT 302), in `playbooks/deploy-iot.yml`, after `roles/mosquitto`

## How it works

1. Installs `prometheus-mqtt-exporter`, the package brings the systemd unit and the `prometheus` user
2. `/etc/default/prometheus-mqtt-exporter` (root, 0600): listen address (`iot_lan_ip`, never the IoT leg) + port and the MQTT login (`MQTT2PROM_MQTT_USER`, `MQTT2PROM_MQTT_PASSWORD`, backslash, quote, backtick and dollar escaped for systemd). systemd reads it before the unit drops to `prometheus`
3. `/etc/prometheus/mqtt-exporter.yaml`: subscribes to `home/+/+` on the local broker, one plain number per topic (`metric_per_topic_config`)
4. The device from the topic goes into the `sensor` label, the last part picks the metric

## Metrics

| Metric | Topic | Labels |
|---|---|---|
| `iot_temperature_celsius` | `home/<device>/temperature` | `sensor`, `topic` |
| `iot_humidity_percent` | `home/<device>/humidity` | `sensor`, `topic` |

- Plus the exporter's own: `mqtt2prometheus_connected`, `received_messages{status,topic}`
- A topic that isn't in `mqtt_exporter_metrics` is ignored

## Settings

| Variable | Default | What |
|---|---|---|
| `mqtt_exporter_broker` | `tcp://127.0.0.1:<mqtt_port>` | The broker |
| `mqtt_exporter_listen` | `iot_lan_ip` | Listen address, LAN only |
| `mqtt_exporter_user`, `mqtt_exporter_password` | `mqtt_user`, `mqtt_password` (vault) | The shared MQTT login |
| `mqtt_exporter_topic_path` | `home/+/+` | Subscription |
| `mqtt_exporter_device_regex`, `mqtt_exporter_metric_regex` | see defaults | Device and metric name from the topic |
| `mqtt_exporter_cache_timeout` | `5m` | A sensor silent this long drops out of `/metrics` |
| `mqtt_exporter_metrics` | temperature, humidity | Topic part → metric name + help |
| `mqtt_exporter_port` | 9641 (`ports.yml`) | Scraped by Prometheus (`iot_sensors` job) |

## Notes

- `/etc/default/...` and the yaml are Debian conffiles, `update.yml` reports them when an upgrade ships new ones
- Test: `curl -s <iot_lan_ip>:9641/metrics | grep iot_`
