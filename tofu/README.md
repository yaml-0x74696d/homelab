# tofu

- OpenTofu builds the pod VMs, the NetBird VM, the edge VM, the Home Assistant OS VM, the storage, log and IoT gateway LXCs with the `bpg/proxmox` provider
- The Debian guests are created from a Debian cloud image, HAOS from its own image (step 3b)
- cloud-init sets the IP, the admin user and the SSH key on the Debian guests
- IPs, VMIDs, the admin user, the SSH key path and the pool paths come from `../ansible/group_vars/all/` (read in `locals.tf`), so OpenTofu and Ansible can't drift apart
- Guest sizes, nodes and MACs are in the `vms` / `lxcs` maps in `locals.tf`

## 1. Login and storage

- The provider logs in with an API token for `root@pam` that is exempt from 2FA
- One exception: API tokens can't set bind mounts, so creating the storage LXC needs `pve_password`, with 2FA turned off for that run
- LXC feature flags are root-only too: on an existing CT, set them on the node (`pct set <vmid> --features nesting=1`), then `tofu plan` shows no diff
- Turn on the **import** content type on the `local` datastore, it's needed for the cloud image (Datacenter → Storage → local → Content → Import)
- Run `ssh-add` with your root key, the provider also uses SSH (for the disk import)

## 2. tfvars

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
```

- Set `pve_api_token` and `vm_password` (the same as `sudo_pass` in the vault)

## 3. LXC template (once per node with an LXC: pve-3 and `iot_node`)

```bash
pveam update && pveam download local debian-13-standard_13.6-1_amd64.tar.zst
```

- If the file name differs from the default, change `lxc_template`

## 3b. HAOS image (once, on pve-3)

Upstream ships `.qcow2.xz`, Proxmox can't unpack xz, so it's unpacked by hand into the import dir (`haos_image`):

```bash
v=<version>   # github.com/home-assistant/operating-system/releases
wget -qO- https://github.com/home-assistant/operating-system/releases/download/$v/haos_ova-$v.qcow2.xz \
  | xz -d > /var/lib/vz/import/haos.qcow2
```

- Only read when the disk is created, HAOS updates itself after that
- The router pins `haos_ip` to `macs.haos` (DHCP reservation), HAOS has no cloud-init

## 4. Apply

The storage CT bind-mounts the pool, so the pool has to exist first:

```bash
cd ../ansible && ansible-playbook playbooks/deploy-storage.yml --limit pve-3
cd ../tofu
tofu init
tofu apply
```

- The pod VMs, the NetBird VM, edge and the HAOS VM have `prevent_destroy`, because their databases live on the VM disk (edge: a recreate takes LAN DNS and every route down)
- Never apply a plan that replaces one of them

## 5. Guest agent on a fresh build

- `vms.tf` has `agent { enabled = true }`, but a fresh Debian guest has no agent yet, so the first apply can hang waiting for it
- for the first apply set it to `false`, then back to `true` after `vm-preparation.yml` (pod VMs) or nixos-anywhere (NetBird, edge) and apply again

## 6. NetBird

`netbird.tf` holds the VPN's groups, Network, policies, nameserver group and setup keys ([ADR 0040](../docs/adr/0040-netbird-policy-as-code.md)). The NetBird VM has to exist first.

- Make a service user `tofu` (dashboard: Team, Service Users, role admin) and a personal access token for it, up to a year. Put it in `netbird_token`
- The management API is LAN-only, so run it from the LAN or a VPN peer that can reach `nb.<domain>`
- Group members are the peer ids in `netbird_peers` in `private.yml`
- The built-in `Default` policy has to be imported once before the first apply
- On a fresh lab import it narrowly: `tofu import -target=netbird_policy.default ...`. If `data.netbird_peer.pod2` blocks the import, use an `import {}` block in the stage-1 targeted apply instead
- The `vpn_dns_*` policies have two rule blocks (udp, tcp). After creating them `tofu plan` must show no diff; if the server keeps only one rule per policy, split into one policy per protocol
- A full plan needs the VM up and a valid token. `data.netbird_peer.pod2` needs pod-2 enrolled, so the first apply is staged:

```bash
tofu plan -out=nb.plan \
  -target=netbird_policy.admin_lan -target=netbird_policy.household_web \
  -target=netbird_policy.vpn_dns_admin -target=netbird_policy.vpn_dns_household \
  -target=netbird_policy.default -target=netbird_network_router.lan \
  -target=netbird_network_resource.edge -target=netbird_network_resource.netbird \
  -target=netbird_network_resource.lan -target=netbird_setup_key.this
tofu apply nb.plan; rm -f nb.plan
# stage 2, once pod-2 is enrolled
tofu plan -out=nb.plan -target=netbird_nameserver_group.lab -target=netbird_dns_settings.this
tofu apply nb.plan; rm -f nb.plan
```

- Plans are written inside `tofu/` (`*.plan` is gitignored) and removed right after, because a saved plan holds secrets in clear

- `tofu output -json netbird_setup_keys` prints the keys, the `routing` one goes in the vault as `vault_netbird_setup_key`
- The keys are one-off and expire after `netbird_setup_key_expiry_seconds` (1 day). A new device, or re-enrolling pod-2, needs a fresh key: `tofu apply -target='netbird_setup_key.this["routing"]' -replace='netbird_setup_key.this["routing"]'` (pick the group), then read it again
- Adopting click-made objects: [docs/netbird-by-hand.md](../docs/netbird-by-hand.md)

## Related

- [ADR 0001: OpenTofu and cloud-init for VMs](../docs/adr/0001-tofu-and-cloud-init-for-vms.md)
- [ADR 0005: prevent_destroy on stateful VMs](../docs/adr/0005-prevent-destroy-on-stateful-vms.md)
- [ADR 0040: NetBird policy as code](../docs/adr/0040-netbird-policy-as-code.md)
