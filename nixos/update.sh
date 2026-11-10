#!/usr/bin/env bash
# update a nixos vm: bump flake, build, switch, sanity check. run from ctl-0 (needs nix).
# usage: update.sh <netbird|edge> [ssh target]
set -euo pipefail

NAME=${1:?usage: $0 <netbird|edge> [ssh target]}
[ -f "$(dirname "$0")/$NAME/configuration.nix" ] || { echo "!! no host nixos/$NAME"; exit 1; }

# host ip from the shared facts (ansible/group_vars), no copy here
fact() { nix run nixpkgs#yq-go -- "$1" "$(dirname "$0")/../ansible/group_vars/all/network.yml"; }
HOST=${2:-root@$(fact ".${NAME}_ip")}
cd "$(dirname "$0")"

PRIVATE="$PWD/../ansible/group_vars/all/private"
[ -f "$PRIVATE/private.yml" ] || { echo "!! $PRIVATE/private.yml missing (cp the example, fill in)"; exit 1; }
# private.yml may be a symlink into the synced private folder; nix copies links, not their targets
PRIVATE=$(dirname "$(realpath "$PRIVATE/private.yml")")
rebuild() { nix run nixpkgs#nixos-rebuild -- "$1" --flake ".#$NAME" --override-input private "path:$PRIVATE" "${@:2}"; }

echo ">> bump flake inputs"
nix flake update

echo ">> build (nothing live yet, catches option renames)"
rebuild build

echo ">> switch $HOST"
rebuild switch --target-host "$HOST"

echo ">> failed units"
failed=$(ssh "$HOST" systemctl --failed --no-legend)
[ -z "$failed" ] || { echo "$failed"; echo "!! failed units, rollback: ssh $HOST nixos-rebuild switch --rollback"; exit 1; }

# booted vs current kernel differ = switch pulled a new one
ssh "$HOST" 'test "$(readlink /run/booted-system/kernel)" = "$(readlink /run/current-system/kernel)"' \
  || echo "!! new kernel, plan a reboot of $HOST"

echo ">> done. commit nixos/flake.lock"
