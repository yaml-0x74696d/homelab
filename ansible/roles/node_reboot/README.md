# node_reboot

- Reboots a host only if it needs one, then waits until it is whole again
- One host at a time, a failure stops the run
- Doesn't upgrade anything: that's `roles/update` and unattended-upgrades

## Runs on

- `playbooks/reboot.yml`: lxc_containers, then pod_vms, then proxmox. Only the hosts `roles/reach` found up
- Semaphore (a template without a schedule, run it when the update summary says `REBOOT due`) or by hand, `-l <host>` works
- Not ctl-1: it runs Semaphore, a reboot would kill the run. `ssh -t ctl-1 sudo reboot` from the controller. Not the NixOS VMs, they reboot in their own window

## How it works

1. Debian: a reboot is due if `/var/run/reboot-required` exists, or needrestart reports a newer kernel or microcode (the same test as `REBOOT due` in the update summary, Debian writes no reboot-required file for a kernel). EL: `needs-restarting -r` exits 1. Read-only, so `--check` shows what a run would reboot
2. Not due: nothing happens to the host
3. Before: the failed units are noted. pve nodes: quorum must be `Yes` (`roles/update`, `tasks/quorum.yml`) and the other nodes must still hold it without this one (`Total votes - 1 >= Quorum`, so no node reboots while another is down). `pvesh` lists the running guests and their `onboot` flag
4. `ansible.builtin.reboot`, waits until ssh answers again. pve stops its guests itself while it shuts down and starts the `onboot` ones after boot. A host that drops off after that counts as failed (`ignore_unreachable` plus a final ping), so the alert still goes out
5. After, pve nodes: quorum again, then every `onboot` guest has to run, and the running guests without `onboot` are started again. All hosts: systemd leaves `starting`, and no unit may have failed that wasn't failed before. Pod VMs, and after a node reboot the pod VMs on that node (`guest_nodes`): every app's user manager has to be `running`, which with `Notify=healthy` means every container passed its health check
6. The last play prints one line per host and pushes it to ntfy, host names only. A failed host pushes an alert and the summary so far, the hosts after it keep their reboot for the next run

## Settings

| Variable | Default | What |
|---|---|---|
| `node_reboot_pve` | `false` | `true` in the pve play: quorum and guest checks |
| `node_reboot_check_kernel` | `true` | needrestart's kernel and microcode check. `false` on the LXCs, they run the node's kernel |
| `node_reboot_timeout` | `900` | Seconds for the host to come back, `1800` in the pve play |
| `node_reboot_boot_time_command` | empty | The reboot module's default (boot_id). The LXC play sets init's start time: the boot_id is the node's and doesn't change |
| `node_reboot_wait_retries` / `node_reboot_wait_delay` | `60` / `10` | Tries and seconds while waiting for a guest, systemd or an app |
| `node_reboot_quorum_retries` / `node_reboot_quorum_delay` | `30` / `10` | Same for quorum after the reboot |
| `node_reboot_summary_hosts` | lxc_containers + pod_vms + proxmox | Hosts the summary covers |
| `node_reboot_ntfy_title` | `homelab reboots` | ntfy title |
| `node_reboot_ntfy_headers` | Title + Bearer `ntfy_token` if set | Headers for every ntfy push |
| `update_quorum_retries`, `update_quorum_delay` | `roles/update` | Set per call here |
| `podman_svc_prefix`, `apps` | group_vars | Which user managers to wait for |
| `ntfy_url`, `ntfy_token`, `ntfy_timeout` | group_vars | Shared ntfy settings, an empty URL sends nothing |

## Notes

- A guest that was running without `onboot` doesn't come back by itself: the run starts it again and its id is in the summary. One that was off stays off
- Gatus isn't asked: it can be down itself (pod-2), the checks above are on the host. Look at Gatus once after the run
- Guests go down twice when their node reboots after them: that's the order, a bad kernel shows on the guests first
- pod-1 takes SSO down for a minute, pod-2 the VPN routing and DNS for VPN clients, pve-1 edge (LAN DNS and every route), pod-1 and the IoT gateway

## Related

- [ADR 0024: OS updates through one Ansible run](../../../docs/adr/0024-ansible-run-os-updates.md) (the reboot stays a separate, deliberate run)
- `roles/update` (quorum check, the summary that says what is due), `roles/reach`
