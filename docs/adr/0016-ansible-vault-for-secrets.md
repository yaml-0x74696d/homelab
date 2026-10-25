# 16. ansible-vault for secrets

Status: Accepted

## Context

- 38 secrets: API tokens, database passwords, OIDC client secrets, SMB passwords, the ntfy topic
- Every app needs some of them at deploy time, but the compose files should stay plain YAML
- The repo is public, so nothing secret may ever land in git

- Alternatives:
  - sops (age keys) (why not: one more tool and key to manage)
  - agenix (why not: Nix only, the Debian hosts can't use it)
  - A secrets manager (e.g. Bitwarden Secrets Manager) (why not: another service that has to run before anything else)
  - Keep secrets in `.env` files by hand (why not: not in git, gets lost)
- Why: already part of Ansible, nothing extra to run

## Decision

The vault:
- One encrypted file, `ansible/group_vars/all/vault.yml` (`ansible-vault`)
- `vault.yml.example` lists all 38 keys without values
- The password is in `ansible/.vault_pass`, read through `vault_password_file` in `ansible.cfg`
- Both files are gitignored here, the real vault only lives on the controller
- Facts that aren't secret stay in the other `group_vars/all/*.yml` files, never in the vault

How apps get their secrets:
- vault → `apps/<name>/.env.j2` → rendered `.env` (mode `0600`) → `${VAR}` in compose

The NetBird box (NixOS):
- Secrets are put on the box by hand under `/var/lib/secrets/` (`secretsDir`)
- The modules read them from those files, so they never end up in the Nix store or in git

- Enforced by: `.gitignore`, plus gitleaks on every commit and over the full history (`just check`, CI)

## Consequences

- Easier: one tool that's already in the stack, no extra key management
- Easier: compose files and templates stay readable, secrets only show up as `${VAR}`

- Harder: vault values must not contain `$`, compose interpolation eats it (bcrypt hashes need `$$`)
- Harder: the vault and `.vault_pass` have to be backed up off the controller by hand
- Harder: two ways secrets get placed: Ansible Vault for the Debian hosts, files by hand on the NetBird box

- Accepted: one password unlocks every secret
- Accepted: agenix/sops for the NixOS box is still open

- Related: [0002](0002-generic-docker-app-role.md) (`.env.j2` pattern), [0008](0008-nixos-for-the-dmz-box.md) (NetBird secrets)
