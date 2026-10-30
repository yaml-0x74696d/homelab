#!/usr/bin/env bash
# review + accept aide changes on the netbird vm and record the db hash. run from ctl-0.
# first run builds the baseline. ansible/aide/netbird.sha256 is gitignored, back it up with the vault.
set -euo pipefail

# netbird ip from the shared facts (ansible/group_vars), no copy here
fact() { nix run nixpkgs#yq-go -- "$1" "$(dirname "$0")/../ansible/group_vars/all/network.yml"; }
HOST=${1:-root@$(fact .netbird_ip)}
SUM="$(cd "$(dirname "$0")" && pwd)/../ansible/aide/netbird.sha256"
CFG=--config=/etc/aide.conf
DB=/var/lib/aide/aide.db

# local expansion of $CFG/$DB is the point
# shellcheck disable=SC2029
remote() { ssh "$HOST" "$@"; }

if ! remote test -f "$DB"; then
  echo ">> no baseline yet, building one (takes a minute)"
  remote "aide $CFG --init >/dev/null && mv $DB.new $DB"
else
  have=$(remote sha256sum "$DB" | cut -d' ' -f1)
  want=$(cat "$SUM" 2>/dev/null || true)
  if [ "$have" != "$want" ]; then
    echo "!! db hash $have doesn't match $SUM (${want:-missing}). find out why before accepting."
    exit 1
  fi

  rc=0
  remote "aide $CFG --update" || rc=$?
  [ "$rc" -ge 14 ] && { echo "!! aide error $rc"; exit 1; }
  [ "$rc" -eq 0 ] && { echo ">> no changes"; exit 0; }

  read -rp "type yes to make this the new baseline: " ans
  [ "$ans" = yes ] || { echo ">> not accepted"; exit 1; }
  remote mv "$DB.new" "$DB"
fi

remote sha256sum "$DB" | cut -d' ' -f1 > "$SUM"
echo ">> recorded $SUM (gitignored, back it up with the vault)"
