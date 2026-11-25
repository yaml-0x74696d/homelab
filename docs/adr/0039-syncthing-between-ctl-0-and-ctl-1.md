# 39. Syncthing between ctl-0 and ctl-1

Status: Accepted

## Context

- ctl-0 and ctl-1 share two things: the accepted AIDE hashes ([0009](0009-aide-with-manual-accept.md)) and the private config overlays (`<private_dir>/apps`, [0031](0031-semaphore-on-a-single-board-computer.md))
- Both went over by hand: `scp` plus `sudo cp` for each accept on ctl-0, `rsync` back after each accept on ctl-1, an rsync task with `-t private-files` for the overlays
- A forgotten copy turned Semaphore's `aide` run red on 2026-11-13: pve-2 and pve-3 were accepted on ctl-0 on the 12th, the hashes never reached ctl-1
- Accepts happen on both sides, so both sides write

- Alternatives:
  - Keep `scp` and `rsync` by hand (why not: the steps get forgotten, and the hashes on ctl-1 need `sudo`)
  - One-way folders, ctl-1 sends the hashes, ctl-0 sends the overlays (why not: an accept on ctl-0 still needs the copy by hand)
  - rsync or unison from a timer (why not: no conflict handling, one more timer and key)
  - Syncthing, both ways (chosen)
- Why: an accept on either side reaches the other within seconds, with nothing to remember

## Decision

The setup:
- Syncthing from Debian on ctl-1 (`syncthing@<admin_user>`, `roles/ctl_base`, `tasks/syncthing.yml`), from the distro on ctl-0, set up by hand (`roles/ctl_base/README.md`)
- Two folders, both send and receive: `homelab-aide` (ctl-1 `/srv/apps/semaphore/aide`, ctl-0 `ansible/aide`) and `homelab-private` (`<private_dir>/apps` on both)
- LAN only: no global discovery, no relays, no NAT traversal, no usage reports. ctl-0 dials ctl-1 on `syncthing_port` (22000), ufw opens it to the LAN only
- GUI and API on `127.0.0.1:8384` on each side. Ansible configures ctl-1 through the API with the key from Syncthing's own `config.xml`
- `ignorePerms` on both folders: a chmod would reset the ACL mask Semaphore reads through
- ACLs on ctl-1's hash dir: `admin_user` for Syncthing, Semaphore's container user for its accepts
- On ctl-0 both folders live in `~/homelab-sync`, outside the secure storage: `private_dir` points there, `ansible/aide` is a symlink into it. Syncthing never touches the folder with the vault password, keys and tofu state
- A daily user timer on ctl-0 (`roles/ctl_base/files/ctl-0/homelab-sync-copy.*`) mirrors `~/homelab-sync` into the secure storage with rsync, one way, so the overlays and hashes keep an off-site copy with the storage's versions
- Simple file versioning on ctl-0's `homelab-aide`: every overwritten hash stays in `.stversions` with its date
- `vault.yml` and `private.yml` keep their copy task (`-t private-files`), they live outside the overlays

- Enforced by: the device list (only ctl-0's id, `syncthing_ctl0_id` in `private.yml`), the ufw rule on ctl-1

## Consequences

- Easier: an accept, a Semaphore run or a new overlay file needs no copy step
- Easier: Syncthing's GUI shows when the two sides differ

- Harder: one more service on each controller, and ctl-0's half is set up by hand
- Harder: both sides changing the same hash at once gives a `.sync-conflict` file to sort out

- Accepted: root on either controller can rewrite the other's hashes and overlays through the sync. ctl-0's copy is not an independent cross-check, its `.stversions` history is
- Accepted: a deleted overlay file is gone on both sides, the versions on ctl-0 only cover the hashes
- Accepted: the off-site copy of the overlays and hashes is up to a day behind

- Related: [0009](0009-aide-with-manual-accept.md) (AIDE), [0031](0031-semaphore-on-a-single-board-computer.md) (ctl-1)
