# 20. Same checks locally and in CI

Status: Accepted

## Context

- One repo with four languages to keep valid: Ansible YAML, OpenTofu, Nix and LikeC4, plus shell scripts and secrets
- Checks that only run in CI get skipped locally, and checks that only run locally get forgotten
- The public repo must never contain a secret
- The first real run on the cleaned repo found 9 issues (8 from ansible-lint, 1 from shellcheck)
- gitleaks in `dir` mode scanned an ignored ansible-lint cache full of third-party test keys. Since then it scans the commits instead

- Alternatives:
  - CI-only workflows per tool (why not: checks get skipped locally, failures only show after the push)
  - A Makefile (why not: just is simpler, no tab/phony quirks)
  - lefthook (why not: smaller ecosystem than pre-commit, fewer ready-made hooks)
  - No checks (why not: the first run found 9 issues)
- The pattern comes from khuedoan/homelab (CI just runs pre-commit) and onedr0p/home-ops (justfile, one CI workflow, actions pinned by SHA)
- Why: one config, the same result locally and in CI

## Decision

The checks (`.pre-commit-config.yaml`, 18 hooks):
- File hygiene: whitespace, end of file, line endings, private keys, shebangs
- Large files: 500 KB in general, 1500 KB for `docs/img/`
- Linters: yamllint, shellcheck, ansible-lint (production profile), `tofu fmt` + `validate`
- Secrets: gitleaks
- The slow hooks only run with `--hook-stage manual`: gitleaks over all commits, `nix flake check`, `likec4 validate`

How to run them (`justfile`):
- `just setup` installs the git hook and the Ansible collections
- `just lint` runs the hooks that also run on commit
- `just check` runs everything, the same as CI

CI (`.github/workflows/`):
- `ci.yml` has one job: `pre-commit run --all-files --hook-stage manual`
- It checks out with `fetch-depth: 0`, so gitleaks sees the whole history
- `pages.yml` builds the LikeC4 site on every push to main (its own trigger, so its own file)
- Actions are pinned by commit SHA, with the tag as a comment
- Tool versions are pinned in the hook revs

Configs:
- `.yamllint`, with rules that fit ansible-lint
- `ansible/.ansible-lint` (`profile: production`), which skips the collections and the Traefik file that uses Go templates

- Enforced by: the git pre-commit hook on every commit, and CI on every push and PR

## Consequences

- Easier: green locally means green in CI, and there's one command to run before pushing
- Easier: secrets are blocked at commit time, and CI scans the full history

- Harder: the local setup needs just, pre-commit, OpenTofu, Nix and Node (the hooks install the rest themselves)
- Harder: the hooks only see files that git tracks, so new files need a `git add` before `just check` sees them

- Accepted: `just check` takes minutes (Nix build of `facts.nix`, the first hook install). Commits stay fast, because the slow hooks only run in the manual stage
- Accepted: the diagram PNGs are committed (exported with `just c4`), so the large-file limit is raised for `docs/img/` only

- Related: [0007](0007-group-vars-single-source-of-truth.md) (OpenTofu + Nix checks read the same facts), [0008](0008-nixos-for-the-dmz-box.md) (flake check)
