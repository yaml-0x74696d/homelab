# Checks

What `just check` and CI run. The checks are pre-commit hooks in `.pre-commit-config.yaml`, so local and CI give the same result ([ADR 0020](adr/0020-same-checks-locally-and-in-ci.md)).

## Run them

From the repo root:

| Command | Runs |
|---|---|
| `just setup` | once per clone: installs the git hook and the Ansible collections |
| `just lint` | the commit-stage hooks, the same as on every `git commit` |
| `just check` | every hook incl. the manual stage, the same as CI |
| `just quadlet` | the rendered units through `quadlet -dryrun` in a Debian container, like `podman.yml` |

The hooks only see files git tracks, a new file needs a `git add` first.

`render-podman` needs `ansible-playbook` (pre-commit installs ansible-core for it) and renders about 20 apps on the controller, which takes about 3 minutes, so it runs on `git push` and only when an input of the render changed (`ansible/apps`, `roles/podman_app`, `group_vars`, the inventory). `just render` runs the same by hand.

## The hooks

Stage: commit = on every commit and `just lint`. push = on `git push`, only the render runs there. manual = `just check` and CI. Hooks without a stage here run in both. The fixers (`render-podman` on push, `gen-role-settings` on commit) don't run in `just check` and CI, those run their `-check` variants.

| Hook | Checks | Script | Stage |
|---|---|---|---|
| `check-added-large-files` | no file over 500 KB, `docs/img/` excluded | pre-commit-hooks | commit |
| `check-added-large-files` (diagrams) | no file in `docs/img/` over 1500 KB | pre-commit-hooks | commit |
| `check-executables-have-shebangs` | executables start with a shebang | pre-commit-hooks | commit |
| `check-shebang-scripts-are-executable` | scripts with a shebang are executable, `.j2` skipped | pre-commit-hooks | commit |
| `check-merge-conflict` | no conflict markers | pre-commit-hooks | commit |
| `detect-private-key` | no private key in a file | pre-commit-hooks | commit |
| `end-of-file-fixer` | one newline at the end of a file | pre-commit-hooks | commit |
| `mixed-line-ending` | LF line endings | pre-commit-hooks | commit |
| `trailing-whitespace` | no trailing spaces (markdown line breaks kept) | pre-commit-hooks | commit |
| `yamllint` | YAML style (`.yamllint`) | yamllint | commit |
| `shellcheck` | shell scripts | shellcheck-py | commit |
| `gitleaks` | secrets in the staged changes | gitleaks | commit |
| `gitleaks` (all commits) | secrets in every commit | gitleaks | manual |
| `actionlint` | workflow syntax and expressions | actionlint | commit |
| `zizmor` | workflow security (template injection, permissions, unpinned actions) | zizmor | commit |
| `tofu_fmt` | OpenTofu formatting | pre-commit-opentofu | commit |
| `tofu_validate` | OpenTofu config is valid | pre-commit-opentofu | commit |
| `ansible-lint` | Ansible, production profile (`ansible/.ansible-lint`) | ansible-lint | commit |
| `check-wiring` | `apps.yml` against what's wired to it: hosts, ports, UIDs, routes, unit templates, PBS jobs, Homepage tiles | `scripts/check_wiring.py` | commit |
| `shellcheck-templates` | `*.sh.j2` rendered with dummy vars, then shellcheck | `scripts/shellcheck_templates.py` | commit |
| `render-podman` | renders `rendered_config/example`. If a file changed, the push stops: commit the render and push again | `scripts/render_podman.sh fix` | push |
| `render-podman-check` | `rendered_config/example` matches what the templates render, nothing is written to git | `scripts/render_podman.sh check` | manual |
| `gen-role-settings` | writes the Settings table of every role README from `meta/argument_specs.yml` and `defaults/main.yml`. If a README changed, the hook fails: `git add` it and commit again | `scripts/gen_role_settings.py` | commit |
| `gen-role-settings-check` | the Settings tables are up to date, nothing is written | `scripts/gen_role_settings.py --check` | manual |
| `apps-schema` | every Podman entry in `apps.yml` against `podman_app`'s argument_specs | `playbooks/ci-validate-apps.yml` | manual |
| `nix-flake-check` | `nix flake check` in `nixos/` | | manual |
| `likec4-validate` | the LikeC4 model parses | | manual |
| `check-c4` | C4 house style: ids, labels, descriptions | `scripts/check_c4.py` | manual |
| `check-adr` | ADR structure: file names and numbering, status line, required sections, the index, links | `scripts/check_adr.py` | commit |

## One hook

```bash
pre-commit run check-wiring --all-files
pre-commit run nix-flake-check --all-files --hook-stage manual
```

A manual-stage hook needs `--hook-stage manual`, without it pre-commit skips it. The scripts also run on their own, e.g. `python3 scripts/check_adr.py`.

## CI

`.github/workflows/`:

| Workflow | Runs | When |
|---|---|---|
| `ci.yml` | `pre-commit run --all-files --hook-stage manual` with `private.yml.example`, a dummy vault password and a throwaway SSH key. zizmor runs as its own step, the only one with the token | push to main/testing, PRs |
| `podman.yml` | `scripts/check_quadlet.sh`: every app in `rendered_config/example` through `quadlet -dryrun -user` in `debian:trixie` (CI only, locally `just quadlet`) | push to main/testing, PRs |
| `pages.yml` | builds the LikeC4 site and deploys it to GitHub Pages (CI only) | push to main that touches `architecture/**` |
