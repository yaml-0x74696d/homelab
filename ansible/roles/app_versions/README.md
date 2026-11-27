# app_versions

- A static page with every app container, the version it runs and the newest tag upstream: `web.<domain>/versions/`
- Read-only on the app hosts: nothing is installed, pulled or restarted

## Runs on

- pod_vms, podman_hosts (`playbooks/app-versions.yml`, Semaphore schedule)
- the page lands on `app_versions_web_host` (the nginx app's host)

## How it works

1. The script module runs `files/app-versions` (Python, stdlib only) as root on every app host. It walks the svc users like `apps ps`, and per running container reads the image's `org.opencontainers.image.version` label and build date
2. Newest tag: `skopeo list-tags`, one lookup per image. A pinned tag (`16-alpine`, `2026.8.3`) is compared against tags of the same shape (`16-alpine` finds `17-alpine`, not `17-bookworm`): a higher one = `newer tag`
3. A floating tag (`latest`, `alpine`) is compared by digest: the tag's digest upstream against the running image's = `current` or `update waiting`. Its newest is the newest release with the same suffix (`1.2.3-alpine`), else a plain one (`1.2.3`, `v1.2`). Without a label, running shows that release when its digest matches. A failed lookup shows `?`, never behind
4. The template collects every host's lines and writes `index.html` into `app_versions_web_dir` on the nginx host. A host that failed is named at the top
5. nginx mounts that dir read-only at `/versions/` (`apps/nginx`, the `versions` dir in `apps.yml`), so a redeploy of nginx doesn't touch the page. Deploy nginx before the first run

## Settings

<!-- settings:start -->
| Variable | Default | What |
|---|---|---|
| `app_versions_web_host` | `apps.nginx.host` | Host whose nginx serves the page |
| `app_versions_web_dir` | `{{ podman_apps_root }}/nginx/versions` | Dir the page is written to, nginx mounts it at /versions/ |
| `app_versions_lookup_timeout` | `60s` | skopeo timeout per registry tag list (Go duration) |
<!-- settings:end -->

## Related

- `roles/podman_base` (installs skopeo)
- [ADR 0021: Podman quadlets](../../../docs/adr/0021-podman-quadlets.md) (auto-update keeps the floating tags fresh)
