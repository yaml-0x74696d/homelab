# NetBird

How a device joins the VPN, what it may reach, and how the VPN is run. Groups, policies, the Network, DNS and the setup keys are in [`tofu/netbird.tf`](../tofu/netbird.tf), the reasons in [ADR 0003](adr/0003-netbird-instead-of-port-forwards.md) and [ADR 0040](adr/0040-netbird-policy-as-code.md).

## Who reaches what

| Group | For | Reaches | Extra rule |
|---|---|---|---|
| `admin` | my own devices | the whole LAN, DNS | |
| `household` | family devices | the web apps on edge (443), DNS | client at least `netbird_min_client_version` |
| `routing` | pod-2 only | routes the LAN for the others, masquerade on | NetBird's DNS management off |

- The apps still ask for their Authentik login, the VPN only opens the path
- The lab domain resolves through the nameserver group `lab` (`dns-relay` on pod-2), the rest of DNS stays with the device
- Groups starting with `res-` hold targets (addresses behind pod-2), not devices
- The management server and the dashboard are `nb.<domain>`. The dashboard answers the LAN and the VPN only

## Onboarding a device

Commands run in `tofu/` on the controller, then on the device.

Devices join with a one-off setup key, not with a login: the IdP isn't reachable from the internet ([`roles/netbird_agent`](../ansible/roles/netbird_agent/README.md#enrollment)).

1. A fresh key for the device's group, on the controller in `tofu/`:

   ```bash
   g=household   # admin, household or routing
   tofu apply -target="netbird_setup_key.this[\"$g\"]" -replace="netbird_setup_key.this[\"$g\"]"
   tofu output -json netbird_setup_keys | jq -r ".$g"
   ```

   - One key per device, it works once and for one day (`netbird_setup_key_expiry_seconds`)
   - The output is the secret, hand it over directly and not through a chat or mail that keeps it
2. On the device, install NetBird from netbird.io (app store on phones), then:
   - Desktop: `netbird up --management-url https://nb.<domain> --setup-key-file <file>` (a file keeps the key out of the process list)
   - Phone: in the app, change the server to `https://nb.<domain>` and enter the setup key there
3. The device shows up in the dashboard under Peers, already in its group. Rename it there to something you recognize
4. Add its peer id to `netbird_peers` in `private.yml`, under the same group. Without it the next apply takes the device out of its group:

   ```bash
   tofu plan -target=netbird_group.admin -target=netbird_group.household -target=netbird_group.routing
   ```

   must show no changes
5. Test from the device on mobile data, not from the home Wi-Fi: Homepage and one app by name

A household device that stays without access runs an older client than `netbird_min_client_version`: update NetBird on it.

## Administration

Commands run in `tofu/` on the controller, the dashboard steps in a browser.

**Moving a device to another group**
- Move its id in `netbird_peers` (`private.yml`), then a targeted apply of the two groups

**Offboarding a device**
1. Take its id out of `netbird_peers`
2. Targeted apply of its group
3. Delete the peer in the dashboard (Peers). In this order, or the group still points at a peer that's gone

**Re-enrolling pod-2**
- A fresh `routing` key ([onboarding step 1](#onboarding-a-device), group `routing`), into the vault as `vault_netbird_setup_key`, then `ansible-playbook playbooks/deploy-netbird-agent.yml`. The role enrolls only when `/etc/netbird/config.json` is missing
- pod-2's peer name has to stay `pod-2`: `data.netbird_peer.pod2` finds its overlay IP by that name for the nameserver group

**Checking for changes made in the dashboard**

```bash
tofu plan $(tofu state list | grep '^netbird_' | sed 's/\[.*//' | sort -u | sed 's/^/-target=/')
```

- No changes means dashboard and code agree. Anything else was clicked: fix the code or revert the click with a targeted apply
- Objects made by hand that aren't in the code don't show up here, look at the dashboard's group and policy lists

**The tofu token**
- Creation: dashboard, Team, Service Users, new user `tofu`, role admin. Make a personal access token for it, up to a year, and put it in `netbird_token` in `terraform.tfvars`, nowhere else
- It lives up to a year. Rotate it before it runs out: dashboard, Team, Service Users, `tofu`, new token, into `terraform.tfvars`, then delete the old one

**Changing what a group may reach**
- A change in `tofu/netbird.tf`, a PR, then a targeted `plan` and `apply` of the policy. ADR 0040 says which rules are intended

**Updates**
- The NetBird VM upgrades itself nightly (`system.autoUpgrade`, [updates.md](updates.md))
- pod-2's client comes with `update.yml`, the devices update through their app store or package manager
- Raise `netbird_min_client_version` when old clients should stop getting in, then a targeted apply of `netbird_posture_check.household_client`

## Troubleshooting

Checks run in the dashboard, `tofu/` on the controller, or on the device.

**A device is connected but reaches nothing**
- Check its group in the dashboard. No group means its id is missing in `netbird_peers`
- Household: the client version is below the posture check

**Names in the lab domain don't resolve, IPs work**
- Reconnect the client, it keeps the old DNS config until then
- The nameserver group `lab` must point at pod-2's current overlay IP: a targeted `plan` of `netbird_nameserver_group.lab` shows when it moved

**The VPN works at home but not on mobile data**
- At home the device reaches the LAN directly. Test only on mobile data
- `rp_filter` on pod-2: [troubleshooting.md](troubleshooting.md), "Routed NetBird traffic drops on pod-2"

## Related

- [ADR 0003: NetBird instead of port forwards](adr/0003-netbird-instead-of-port-forwards.md)
- [ADR 0040: NetBird policy as code](adr/0040-netbird-policy-as-code.md)
- [tofu/README.md, step 6](../tofu/README.md#6-netbird): the first apply on a fresh lab
- [netbird-by-hand.md](netbird-by-hand.md): adopting a dashboard made by hand
- [`roles/netbird_agent`](../ansible/roles/netbird_agent/README.md): pod-2's client
