#!/usr/bin/env bash
# every app in rendered_config/example through `quadlet -dryrun -user`, as a throwaway user like svc-<app>.
# needs root and podman, ci runs it in debian (.github/workflows/podman.yml)
set -euo pipefail
shopt -s nullglob

quadlet=${QUADLET:-/usr/libexec/podman/quadlet}
ci_user="quadlet-ci"
repo=$(cd "$(dirname "$0")/.." && pwd)
example_dir="$repo/rendered_config/example"

id "$ci_user" >/dev/null 2>&1 || useradd -m "$ci_user"
unit_dir=$(getent passwd "$ci_user" | cut -d: -f6)/.config/containers/systemd

failed=0
for app_dir in "$example_dir"/*/; do
    app=$(basename "$app_dir")
    # one app per run: container.d/ is per app, like each svc user's own dir
    rm -rf "$unit_dir"
    install -d -o "$ci_user" "$unit_dir"
    # units and drop-in dirs only, config/ and secrets/ stay out
    find "$app_dir" -mindepth 1 -maxdepth 1 \( -name '*.container' -o -name '*.pod' -o -name '*.volume' \
        -o -name '*.network' -o -name '*.image' -o -name '*.build' -o -name '*.kube' -o -name '*.d' \) \
        -exec cp -r -t "$unit_dir" {} +
    chown -R "$ci_user" "$unit_dir"

    if ! out=$(runuser -l "$ci_user" -c "$quadlet -dryrun -user" 2>&1); then
        echo "ERROR $app: quadlet failed"
        echo "$out"
        failed=1
        continue
    fi
    app_ok=1
    # quadlet only logs a file it doesn't know, so check every unit came out
    for unit in "$unit_dir"/*.container; do
        name=$(basename "$unit" .container)
        if ! grep -Eq -- "^---(.*/)?$name\.service---$" <<<"$out"; then
            echo "ERROR $app: no $name.service in the dryrun"
            echo "$out"
            app_ok=0 failed=1
        fi
    done
    if [ "$app_ok" = 1 ]; then echo "ok    $app"; fi
done

exit "$failed"
