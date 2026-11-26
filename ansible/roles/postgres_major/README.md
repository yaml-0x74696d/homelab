# postgres_major

- Moves an app's Postgres container to a higher major: dump, swap the data dir, deploy the new tag, import, start the app
- Keeps the old data dir and the dump, deleting them is a separate, later step
- Plain `postgres` images only. Immich's vectorchord build is refused, it follows its release notes

## Runs on

- The app's host (`playbooks/postgres-major.yml -e app=<name>`), by hand from the controller. The apps with a plain Postgres: authentik, nextcloud, paperless
- `--check` runs the checks and prints the plan, nothing is touched

## The order

1. Raise the db tag in `group_vars/all/apps.yml` (`16-alpine` → `17-alpine`), commit and pull it where you run the playbook. Don't deploy it: the new image can't open the old data dir
2. `ansible-playbook playbooks/postgres-major.yml -e app=<name>`

The tag goes first, because `apps.yml` is the declared state: the playbook reads the new major from it and the old one from the running container, and never edits the repo. The other way round (`-e tag=…`) would leave `apps.yml` on the old major, and the next `deploy-app.yml` would try to start the old image on the new data.

## How it works

1. Checks, all read-only: one container on `docker.io/library/postgres`, its tag starts with a major, the running container is the old major and the new one is higher, the data dir is a `dirs:` entry of the app, the folder for the old dir doesn't exist yet. Counts the tables of the old db
2. Stops the app's other containers, so nothing is written from here. The old db keeps running
3. `pg_dump --clean --if-exists` from the running old container into `<app dir>/pg-major/<app>-pg<old>.sql` (mode `0700` folder). The file has to end with pg_dump's completion line
4. Stops the old db, moves its data dir to `<dir>.pg<old>-<date>`
5. Deploys through `roles/podman_app`: the empty data dir, the unit with the new tag, a start. The app comes up on the empty db, as in the restore after a rebuild ([bootstrap, step 7](../../../docs/bootstrap.md#7-restore-the-data)), then it is stopped again
6. `pg_isready`, then `psql --single-transaction` with `ON_ERROR_STOP` imports the dump. A failed import leaves the new db empty
7. Checks the new db: the major, and the same number of tables as before
8. Starts the app and asks its first route (a redirect to the login counts)
9. Prints how to delete the old dir and the dump

A failure before step 4 starts the old db and the app again, nothing was moved. After step 4 it stops and prints how to go back or forward. Not resumable: the old db has to be running at the start.

## Settings

| Variable | Default | What |
|---|---|---|
| `postgres_major_app` | required | The app's key in `apps.yml`, set from `-e app=` |
| `postgres_major_images` | `[docker.io/library/postgres]` | Images that count as plain Postgres |
| `postgres_major_pgdata_change` | `18` | First major refused, see Notes |
| `postgres_major_dir` | `pg-major` | Folder in the app's dir for the dump and the import log |
| `postgres_major_ready_retries` / `postgres_major_ready_delay` | `30` / `5` | Tries and seconds until the new Postgres answers |
| `postgres_major_route_codes` | 200, 204, 301, 302, 303, 307, 308, 401 | Status codes that count as up |
| `postgres_major_route_retries` / `postgres_major_route_delay` | `30` / `10` | Tries and seconds on the first route |
| `podman_apps_root`, `podman_svc_prefix`, `domain`, `apps` | group_vars | Where the apps live, who runs them, the route |

## Notes

- Downtime is the dump, the new image's first start and the import. The app is stopped for all of it
- Majors from 18 on are refused: the official image keeps PGDATA below `/var/lib/postgresql/<major>/`, our units mount `/var/lib/postgresql/data`, so the data would land in an anonymous volume. Change the db template and the data dir first
- The old dir and the dump sit in the app's dir, so PBS backs them up until you delete them (only the live `data_dir` of `pbs_jobs` is excluded). AIDE doesn't look at `/srv/apps`
- No passwords are passed or printed: the commands run inside the container with its own environment. The dump and the import log hold data, so they are kept in files (stderr too) and never in the run output
- A pod is stopped per container, not as a whole, so the db stays up for the dump
- Authentik migrates the empty db on that first start, which can take minutes (`start_timeout`). `deploy-authentik.yml`'s guards aren't involved, the authentik tag doesn't change

## Related

- `roles/podman_app` (the deploy), `roles/pbs` (the nightly dump the restore steps use)
- [docs/updates.md](../../../docs/updates.md#pinned-images)
