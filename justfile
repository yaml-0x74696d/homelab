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

# deploy one app, e.g. just deploy immich
deploy app:
    cd ansible && ansible-playbook playbooks/deploy-{{ app }}.yml

# export every view as png for the docs
c4:
    {{ likec4 }} export png architecture --outdir {{ img_dir }} --flat --seq
