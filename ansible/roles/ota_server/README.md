# ota_server

- Serves the sensors' firmware files over plain HTTP, so devices pull their updates from the gateway
- Debian's `nginx`, on the IoT leg only, read-only, no directory listing

## Runs on

- The IoT gateway LXC (CT 302), in `playbooks/deploy-iot.yml`. The playbook also sets the LXC's ufw rules

## How it works

1. Installs `ota_server_package`
2. `/srv/firmware` (root, 0755): the `.bin` files, copied there by hand with scp over the LAN leg
3. Drops Debian's default site (`sites-enabled/default`, it listens on every address)
4. `/etc/nginx/conf.d/ota.conf`: one server on `iot_ip:ota_port`, GET/HEAD only, files only (anything else is a 404), logs to syslog, so rsyslog ships them to the log LXC
5. `nginx -t` before the restart handler

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `ota_server_package` | `nginx` | firmware downloads for the iot net, nothing else on this nginx |
| `ota_server_listen` | `iot_ip` | iot leg only, never the lan |
| `ota_server_port` | `ota_port` | listen port (ports.yml, 80) |
| `ota_server_root` | `/srv/firmware` | .bin files, uploaded by hand (scp over the lan leg) |
<!-- settings:end -->

## Notes

- Upload: `scp <device>.bin root@<iot_lan_ip>:/srv/firmware/`. nginx runs as `www-data`, files need to be world-readable (scp's default 0644 is fine)
- AIDE watches `/srv/firmware`: every upload shows up in the next check, accept it with `aide-accept.yml -l iot`
- Test from the gateway: `curl -sI http://<iot_ip>/<device>.bin` (200), `curl -sI http://<iot_ip>/` (404)
- Logs: `journalctl -u nginx`

## Related

- [ADR 0028: IoT gateway LXC](../../../docs/adr/0028-iot-gateway-lxc.md)
