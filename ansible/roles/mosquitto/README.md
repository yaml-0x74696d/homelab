# mosquitto

- The MQTT broker, Mosquitto from Debian's repo
- One shared user for every sensor and consumer, no TLS, plain `mqtt_port` (accepted risk)

## Runs on

- The IoT gateway LXC (CT 302), in `playbooks/deploy-iot.yml`. The playbook also sets the LXC's ufw rules

## How it works

1. Installs `mosquitto` and `mosquitto-clients`
2. Compares a salted sha512 of `user:password` with the one in `/etc/mosquitto/passwd.sum` (root, 0600). No clear copy stays on disk
3. When they differ, or `/etc/mosquitto/passwd` doesn't exist yet: pipes `user:password` into a root-only temp file, hashes it with `mosquitto_passwd -U` and installs it as `/etc/mosquitto/passwd` (mosquitto:mosquitto, 0600, Mosquitto 2.0 warns on any other owner). Then writes the new checksum. `mosquitto_passwd` salts every hash, so the hash itself can't be compared
4. Deletes `/etc/mosquitto/passwd.clear` if it's there, so no clear copy stays
5. `/etc/mosquitto/conf.d/homelab.conf`: the listener, no anonymous logins, the password file, logs to syslog too
6. Debian's `mosquitto.conf` stays as it is: persistence in `/var/lib/mosquitto`, log file in `/var/log/mosquitto`

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `mosquitto_port` | `mqtt_port` | Listener |
| `mosquitto_user` | `mqtt_user` | The shared user |
| `mosquitto_password` | `mqtt_password` | Its password (vault) |
| `mosquitto_passwd_file` | `/etc/mosquitto/passwd` | Hashed password file |
| `mosquitto_passwd_sum_file` | `/etc/mosquitto/passwd.sum` | Salted sha512 of user:password, root only, decides when to rehash |
| `mosquitto_passwd_salt` | `mqtt_passwd_salt` | Salt for that checksum (vault), change it to force a rehash |
<!-- settings:end -->

## Notes

- Test: `mosquitto_sub -h <ip> -u <user> -P <password> -t '#' -v`
- `/var/lib/mosquitto` is left out of AIDE (`lxc_containers` excludes)

## Related

- [ADR 0028: IoT gateway LXC](../../../docs/adr/0028-iot-gateway-lxc.md)
- `mqtt_exporter` role (reads the topics)
