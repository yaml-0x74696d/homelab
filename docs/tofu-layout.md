# OpenTofu layout

Where things are kept in `tofu/`, where its values come from, and how a change is applied without touching the rest.

## Where does it go

| To change | File |
|---|---|
| a guest's cores, RAM, disk, node | `vms` / `lxcs` map in `locals.tf` |
| an IP, a VMID, the IoT node | `ansible/group_vars/all/network.yml` |
| a MAC | `ansible/group_vars/all/private/private.yml` |
| the admin user, the SSH key path | `ansible/group_vars/all/hosts.yml` |
| a pool path, a bind mount | `ansible/group_vars/all/storage.yml` |
| a VM's hardware, cloud-init, lifecycle | `vms.tf` |
| an LXC's mounts, features, NICs | `lxc.tf` |
| the API token, the cloud-init password | `terraform.tfvars` (not in git) |
| the image URL, the LXC template, datastores | `variables.tf` defaults |
| the provider version, login | `providers.tf` |

## Folders

```
tofu/
├── providers.tf               provider pin, login (token, SSH for the disk import)
├── variables.tf               inputs: credentials, image, template, datastores
├── locals.tf                  group_vars read in, the guest maps
├── vms.tf                     cloud images, docker-1/2/3, netbird, haos
├── lxc.tf                     storage, log, iot
├── terraform.tfvars.example   the keys for terraform.tfvars
└── README.md                  first setup, step by step
```

- Gitignored: `terraform.tfvars`, `*.tfstate*`, `.terraform/`, `*.plan`
- State is kept locally in `tofu/`, there is no remote backend

## Where the values come from

- `locals.tf` reads `network`, `ports`, `hosts`, `storage` and `private/private.yml` with `yamldecode(file(...))`. The same files are read by Ansible and NixOS ([ADR 0007](adr/0007-group-vars-single-source-of-truth.md))
- Only what OpenTofu alone needs is kept here: sizes and nodes in the maps, credentials in tfvars
- One resource per kind, `for_each` over a map: a guest is added by adding a map entry (`docker` VMs, the image per node). netbird and the LXCs differ too much and are written out

## Which value is used

Weak to strong:

| # | Source | |
|---|---|---|
| 1 | `default` in `variables.tf` | image URL, template, datastores |
| 2 | `TF_VAR_<name>` environment variables | |
| 3 | `terraform.tfvars` | token, `vm_password` |
| 4 | `*.auto.tfvars` | |
| 5 | `-var-file`, `-var` | |

- `locals` can't be overridden from outside: a value from group_vars is changed in group_vars, nowhere else

## Lifecycle

| Setting | Where | Why |
|---|---|---|
| `prevent_destroy = true` | docker VMs, netbird | the databases are on the VM disk ([ADR 0005](adr/0005-prevent-destroy-on-stateful-vms.md)) |
| `ignore_changes = [url]` | cloud images | Proxmox doesn't keep the source URL, imported files have none |
| `ignore_changes = [disk[0].import_from]` | VMs | the image only counts when the disk is created |
| `ignore_changes = [initialization]` | netbird | NixOS owns disk and network after the bootstrap |
| `ignore_changes = [template_file_id, user_account]` | LXCs | only counted at creation |
| `reboot_after_update = false` | VMs | a change that needs a reboot waits for a planned one |

## Plan and apply

```
tofu plan                                            # full, read-only, should say "No changes"
tofu plan -target='proxmox_virtual_environment_container.iot' -out=/tmp/iot.plan
tofu apply /tmp/iot.plan && rm /tmp/iot.plan
```

- The full plan is safe and run often, the full apply never: only targeted plans are applied
- `-out` makes the apply run exactly what was reviewed. The plan file holds `vm_password` unmasked, so it's removed right after
- A guest that exists already is taken over with `tofu import`, then the code is fixed until the plan is empty

## Conventions

- A value that Ansible or NixOS also needs goes in group_vars and is read in `locals.tf`, never typed twice
- A stateful guest gets `prevent_destroy`
- A field that only counts at creation, or that another tool owns afterwards, goes in `ignore_changes` with a comment why
- Root-only settings (LXC feature flags, bind mounts) are set on the node with `pct set`, the code is matched until the plan is empty
- `tofu fmt` and `tofu validate` run in pre-commit and CI
