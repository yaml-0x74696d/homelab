# 36. AI assistant in a sandbox without access to the lab

Status: Accepted

## Context

- I run the lab alone, so nobody else looks at my changes
- An AI assistant (Claude Code) gives a second pair of eyes and a fresh view, and takes over checks and drafts I would skip
- What makes AI-assisted work safe is not the assistant, it's the checks in the pipeline and the review before anything lands
- Example: the unattended-upgrades config matched no Debian repository and passed every hook. A review found it, and the fix added a check that fails when no Debian-Security source exists (issue #32). A check only catches what someone thought to test, so the review stays
- An assistant reads text from the web and the repo. Injected text or a plain mistake can steer it
- ctl-0 holds the SSH keys and the vault

- Alternatives:
  - Assistant with SSH to the hosts (why not: an injected or wrong session reaches the lab)
  - Cloud agent that pushes to the repo (why not: changes land without my review)
  - Assistant on ctl-0 (why not: ctl-0 holds the keys and the vault)
  - Assistant in a sandbox on its own VM, without access to the lab (chosen)

## Decision

Who does what:
- I design, plan, write and check. Every design choice is mine
- Claude Code is a tool: it runs the checks, generates the C4 model, writes drafts I rewrite, and reviews my changes as a second pair of eyes

The sandbox (its own VM, `claude`, VM 400 on pve-3):
- bubblewrap around the whole session: the home is read-only apart from its work folders, secrets and host sockets are hidden
- No network interface. socat passes one unix socket into the sandbox, and that socket leads to tinyproxy on the VM
- tinyproxy only allows an allowlist of hosts on port 443 and denies everything else. An nft table keeps tinyproxy itself away from the LAN
- No SSH keys, so it can't log in to any host
- Its own rules and settings are read-only, so it can't widen them
- Claude Code's own per-command sandbox runs inside as well

How a change gets in:
1. Claude drafts in the sandbox, I rewrite it
2. The pre-commit hooks run, the same as in CI ([0020](0020-same-checks-locally-and-in-ci.md)): linters, the `apps.yml` schema and wiring check, the ADR check, gitleaks. `just quadlet` puts the Podman units through `quadlet -dryrun`, like the `podman` workflow
3. I review the diff and commit it on `testing`, CI runs again on the push
4. `testing` reaches `main` only through a PR, and the `checks` CI job must pass. GitHub asks for no approvals, I am the only reviewer
5. Deploys start dry: `--check --diff` for Ansible, `tofu plan` for OpenTofu, `update.sh` builds before it switches on NixOS

- Enforced by: the sandbox keeps the assistant away from the lab, the hooks, CI and the branch rules on `main` keep a bad change out, whoever wrote it. Steps 1, 3 and 5 are my habit, not enforced by a machine

## Consequences

- Easier: checks, drafts and the C4 model get done that I would skip alone

- Harder: every change costs a handoff. I copy, review, commit and deploy it myself

- Accepted: the assistant can be wrong. The checks and my review are the controls, and a check can only catch what it tests
- Accepted: the allowed hosts (GitHub, npm and the rest of the allowlist) could still carry injected text, or take data out

- Related: [0016](0016-ansible-vault-for-secrets.md) (vault), [0020](0020-same-checks-locally-and-in-ci.md) (checks)
