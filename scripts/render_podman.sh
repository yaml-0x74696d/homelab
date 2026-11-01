#!/usr/bin/env bash
# every podman app's files rendered with the example values for review (ansible/playbooks/render-podman.yml).
#   example  -> rendered_config/example (in git)
#   check    example, then fail if rendered_config/example differs from git (ci)
set -euo pipefail

mode=${1:?usage: render_podman.sh example|check}
repo=$(git rev-parse --show-toplevel)
example_dir="$repo/rendered_config/example"
collections="$repo/ansible/collections:$HOME/.ansible/collections:/usr/share/ansible/collections"

case "$mode" in
example | check)
    # a copy without ignored files plus the examples: nothing from private.yml or the vault gets in
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cd "$repo"
    git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do [ -e "$f" ] && printf '%s\0' "$f"; done \
        | xargs -0 cp --parents -P -t "$tmp"
    cp "$tmp/ansible/group_vars/all/private/private.yml.example" "$tmp/ansible/group_vars/all/private/private.yml"
    # every vault value as <vault:key>, nested ones (smb_passwords) as <vault:parent.key>
    awk '
        /^[A-Za-z0-9_]+:[[:space:]]*$/ { parent = $1; sub(/:$/, "", parent); print; next }
        /^[A-Za-z0-9_]+:/ { k = $1; sub(/:$/, "", k); print k ": \"<vault:" k ">\""; next }
        /^[[:space:]]+[A-Za-z0-9_-]+:/ { match($0, /^[[:space:]]+/); k = $1; sub(/:$/, "", k)
                                         print substr($0, 1, RLENGTH) k ": \"<vault:" parent "." k ">\""; next }
        { print }
    ' "$tmp/ansible/group_vars/all/vault.yml.example" > "$tmp/ansible/group_vars/all/vault.yml"
    echo dummy > "$tmp/ansible/.vault_pass"

    # ci has no collections dir, ansible-lint keeps its own
    if ! ANSIBLE_COLLECTIONS_PATH="$collections" ansible-galaxy collection list community.general >/dev/null 2>&1; then
        ansible-galaxy collection install -r ansible/requirements.yml -p "$tmp/collections" >/dev/null
        collections="$tmp/collections:$collections"
    fi

    cd "$tmp/ansible"
    ANSIBLE_COLLECTIONS_PATH="$collections" ansible-playbook playbooks/render-podman.yml \
        -e render_dir="$example_dir" -e private_dir=''

    if [ "$mode" = check ] && [ -n "$(git -C "$repo" status --porcelain -- rendered_config/example)" ]; then
        git -C "$repo" status --short -- rendered_config/example
        echo "rendered_config/example is stale: run scripts/render_podman.sh example and commit it" >&2
        exit 1
    fi
    ;;
*)
    echo "usage: render_podman.sh example|check" >&2
    exit 2
    ;;
esac
