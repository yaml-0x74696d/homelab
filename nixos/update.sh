#!/usr/bin/env bash
# update the netbird VM: bump flake, build, switch, sanity check. run from ctl-0 (needs nix).
set -euo pipefail

# netbird ip from the shared facts (ansible/group_vars), no copy here
fact() { nix run nixpkgs#yq-go -- "$1" "$(dirname "$0")/../ansible/group_vars/all/network.yml"; }
HOST=${1:-root@$(fact .netbird_ip)}
cd "$(dirname "$0")"

rebuild() { nix run nixpkgs#nixos-rebuild -- "$1" --flake .#netbird "${@:2}"; }

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
