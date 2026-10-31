# mosquitto

- The MQTT broker, Mosquitto from Debian's repo
- One shared user for every sensor and consumer, no TLS, plain `mqtt_port` (accepted risk)

## Runs on

- The IoT gateway LXC (CT 302), in `playbooks/deploy-iot.yml`. The playbook also sets the LXC's ufw rules

## How it works

1. Installs `mosquitto` and `mosquitto-clients`
2. Writes `user:password` to `/etc/mosquitto/passwd.clear` (root, 0600)
3. When that file changes, or `/etc/mosquitto/passwd` doesn't exist yet: hashes a copy with `mosquitto_passwd -U` and installs it as `/etc/mosquitto/passwd` (mosquitto:mosquitto, 0600, Mosquitto 2.0 warns on any other owner). The hash is salted, so it doesn't run on every pass
4. `/etc/mosquitto/conf.d/homelab.conf`: the listener, no anonymous logins, the password file, logs to syslog too
5. Debian's `mosquitto.conf` stays as it is: persistence in `/var/lib/mosquitto`, log file in `/var/log/mosquitto`

## Settings

| Variable | Default | What |
|---|---|---|
| `mosquitto_port` | `mqtt_port` | Listener |
| `mosquitto_user` | `mqtt_user` (`app_settings.yml`) | The shared user |
| `mosquitto_password` | `mqtt_password` (vault) | Its password |
| `mosquitto_passwd_file` | `/etc/mosquitto/passwd` | Hashed password file |

## Notes

- Test: `mosquitto_sub -h <ip> -u <user> -P <password> -t '#' -v`
- `/var/lib/mosquitto` is left out of AIDE (`lxc_containers` excludes)
