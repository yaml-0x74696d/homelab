# 4. mergerfs instead of ZFS

Status: Accepted

## Context

- pve-3 has 4 data disks of mixed sizes: 3× 3 TB and 1× 2 TB, about 11 TB together
- pve-3 also holds the PBS datastore
- Data: media, Nextcloud files, photos, documents, ISO images, Time Machine backups, other backups

- Alternatives:
  - ZFS RAIDZ (why not: RAM overhead, wastes space with mixed disk sizes)
  - SnapRAID + mergerfs (why not: needs a parity disk and sync jobs)
  - Keep separate disks (why not: no merged file system)
- Why: one merged file system, easy to set up and use, no overhead

## Decision

The pool (`roles/mergerfs`):
- Four plain ext4 disks, mounted by UUID (`defaults,noatime`)
- mergerfs joins them into one folder, `/mnt/storage/pool`
- New files go to the disk with the most free space (`category.create=mfs`)
- A disk with less than 20 GB free gets no new files (`minfreespace=20G`)
- Other options: `cache.files=partial`, `dropcacheonclose=true`, `use_ino`, `allow_other`
- The pool only mounts once all four disks are there (`x-systemd.requires`, `mergerfs_require_disks`)

The sharing (`roles/samba`):
- The pool is bind-mounted into the unprivileged storage LXC at `/srv/storage`
- The pool root belongs to the CT's mapped root user (UID 100000)
- Samba in the CT has one share per service, each with its own service user
- The admin user is in every share's group
- Share GIDs are `samba_gid_base` + the share's position in the list
- UIDs are pinned (`samba_admin_uid`, `samba_svc_uid_base`), so a rebuilt CT keeps the same ownership
- The Time Machine share has a size cap (`tm_size`)
- SMB3 is the minimum, and ufw only allows the LAN

Who uses it:
- The Docker VMs mount their share over CIFS ([0002](0002-generic-docker-app-role.md))
- Databases stay on the local VM disks
- PBS gets its own 100 GB thin LV on the SSD, separate from the HDD pool

- Enforced by: `roles/mergerfs` + `roles/samba` (`deploy-storage.yml`), and the pool doesn't mount unless every disk is there

## Consequences

- Easier: the disks stay plain ext4, so each one can be read on any Linux box on its own
- Easier: the CT can be rebuilt without touching the data, because the data lives on the host

- Harder: `samba_shares` can only be added to at the end. The position in the list sets the GID, so reordering breaks ownership

- Accepted: no parity. A dead disk loses only the files on that disk, the rest of the pool keeps working
- Accepted: configs and databases are backed up by PBS, bulk media is not on purpose (it can be ripped or synced again)

- Related: [0002](0002-generic-docker-app-role.md) (CIFS mounts), [0005](0005-prevent-destroy-on-stateful-vms.md) (DBs stay local)
