# Adopting an existing NetBird dashboard

A guide for taking over click-made NetBird objects with `tofu import`, e.g. on a rebuild or a second lab. The end state is `tofu/netbird.tf` ([ADR 0040](adr/0040-netbird-policy-as-code.md)). On a fresh lab skip this and follow [bootstrap step 4](bootstrap.md).

## 1. Inventory

- Everything the dashboard holds now, as JSON, into the private folder (`private_dir`), not into git
- The PAT comes from step 2, so do that part first

```bash
export NB=https://nb.<domain>/api
read -rs NB_PAT                                    # paste the token, nothing in history or argv
d=<private_dir>/netbird-inventory; mkdir -p $d
for r in peers groups policies posture-checks networks routes dns/nameservers dns/settings setup-keys users; do
  printf 'header = "Authorization: Token %s"\n' "$NB_PAT" | curl -s -K - $NB/$r > $d/${r//\//-}.json
done
```

- `-K -` reads the header from stdin, so the token never shows in `ps`. `printf` is a builtin, so it isn't in argv either
- In fish: `read -s -x NB_PAT` and `set -x NB https://nb.<domain>/api`

- The setup key list has the key names only, not the keys. The keys are one-off, so the tofu ones are new and each device needs its own
- Peer ids for `netbird_peers` and import ids come from `peers.json`, `groups.json` and so on

## 2. Service user and PAT

- Dashboard: Team, Service Users, new user `tofu`, role admin
- Make a personal access token for it, lifetime up to a year
- It goes in `netbird_token` in `terraform.tfvars`, nowhere else

## 3. Groups

- Peer groups: `admin`, `household`, `routing`. Put pod-2 in `routing` and your own devices in `admin`
- Resource-only groups (they stay empty of peers): `res-edge`, `res-netbird`, `res-lan`. Never put a peer and a resource in one group

## 4. Network and resources

- Network `lan`
- Router: peer group `routing`, masquerade on
- Resources: `edge` (`<edge_ip>/32`) in `res-edge`, `netbird` (`<netbird_ip>/32`) in `res-netbird`, `lan` (`<lan_cidr>`) in `res-lan`

## 5. Policies

- `admin-lan`: `admin` to `res-lan`, all protocols
- `household-web`: `household` to `res-edge`, TCP 443
- `vpn-dns-admin-udp`, `vpn-dns-admin-tcp`, `vpn-dns-household-udp`, `vpn-dns-household-tcp`: the source group to `routing`, the `dns-relay` port (`apps.yml`), one policy per protocol
- After creating the DNS policies, `tofu plan` must show no diff. If the server keeps only one rule per policy, split them into one policy per protocol
- A posture check with the minimum client version on the two household policies
- No policy from `household` to `res-netbird`

## 6. DNS

- Nameserver group `lab`: pod-2's overlay IP, the `dns-relay` port, UDP, domain `<domain>`, groups `admin` and `household`
- DNS settings: disable DNS management for `routing`

## 7. Legacy route and the first test

- Disable the old network route for the LAN (Network Routes), the new Network replaces it
- Test from a phone hotspot, not from the LAN, with a device in `admin`:

```bash
netbird status -d                        # connected, the routing peer listed, routes present
ping <pod2_ip>
ssh <admin_user>@<pod2_ip>
dig @<pod2 overlay ip> -p <dns-relay port> <app>.<domain>
curl -I https://<app>.<domain>           # an https app through edge
```

- The dashboard shows the peers online and the policies hit

## 8. Default policy off and the household test

- Disable the `Default` policy (all to all)
- With a device in `household`, on mobile data:
  - an app loads over https
  - a LAN port other than 443 times out, for example `nc -zv -w3 <pod1_ip> 22`
  - the management connection stays up when the VPN is toggled off and on: the client has to resolve `nb.<domain>` to the NetBird VM through the AdGuard rewrite, check `netbird status -d` after the toggle
- Check on purpose: household to `res-netbird` is not allowed, so the device must still reach management through its normal path. If it drops after a toggle, that is the reason to add the policy

## 9. Import into tofu

- Fill in `netbird_peers` in `private.yml` first
- Ids are in the inventory JSON. Import one resource at a time:

```bash
cd tofu
tofu import netbird_group.admin <id>
tofu import netbird_group.household <id>
tofu import netbird_group.routing <id>
tofu import netbird_group.res_edge <id>
tofu import netbird_group.res_netbird <id>
tofu import netbird_group.res_lan <id>
tofu import netbird_network.lan <network id>
tofu import netbird_network_router.lan <network id>/<router id>
tofu import netbird_network_resource.edge <network id>/<resource id>
tofu import netbird_network_resource.netbird <network id>/<resource id>
tofu import netbird_network_resource.lan <network id>/<resource id>
tofu import netbird_posture_check.household_client <id>
tofu import netbird_policy.admin_lan <id>
tofu import netbird_policy.household_web <id>
tofu import 'netbird_policy.vpn_dns_admin["udp"]' <id>
tofu import 'netbird_policy.vpn_dns_admin["tcp"]' <id>
tofu import 'netbird_policy.vpn_dns_household["udp"]' <id>
tofu import 'netbird_policy.vpn_dns_household["tcp"]' <id>
tofu import netbird_policy.default <id>
tofu import netbird_nameserver_group.lab <id>
```

- DNS settings have no import, and a setup key's plaintext can't be read back. Both are created by the apply, the setup keys are new one-off ones
- Then `tofu plan`. It has to show no changes except those two. Fix `netbird.tf` or the dashboard until it does, never apply a plan that destroys a policy or a group
