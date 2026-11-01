set shell := ["bash", "-euo", "pipefail", "-c"]

likec4 := "npx -y likec4@1.60.0"
img_dir := "docs/img"

# list recipes
default:
    @just --list

# once per clone: git hooks + ansible collections
setup:
    pre-commit install
    cd ansible && ansible-galaxy collection install -r requirements.yml -p collections
    @test -f ansible/.vault_pass || echo "create ansible/.vault_pass before running playbooks"

# fast checks (same as on commit)
lint:
    pre-commit run --all-files

# every check incl. nix flake + likec4 (same as ci)
check:
    pre-commit run --all-files --hook-stage manual

# deploy one compose app, e.g. just deploy immich
deploy app:
    cd ansible && ansible-playbook playbooks/deploy-{{ app }}.yml

# deploy one podman app from apps.yml, e.g. just deploy-app gatus
deploy-app app:
    cd ansible && ansible-playbook playbooks/deploy-app.yml -e app={{ app }}

# podman apps rendered with the example values: rendered_config/example
render:
    scripts/render_podman.sh example

# export every view as png for the docs
c4:
    {{ likec4 }} export png architecture --outdir {{ img_dir }} --flat --seq

# render the d2 diagrams as svg for the docs
diagrams:
    for f in docs/diagrams/*.d2; do d2 "$f" {{ img_dir }}/$(basename "$f" .d2).svg; done
