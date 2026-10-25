# file integrity for the wan box. only state an upgrade never touches: autoUpgrade rewrites the
# system links daily, and store paths are checked by nix anyway. accept + hash: nixos/aide-accept.sh
{ config, pkgs, facts, ... }:
let
  checkNice = 19;

  conf = pkgs.writeText "aide.conf" ''
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    gzip_dbout=yes
    # activation rewrites /etc files, so content + perms only, no times/inodes
    Content = p+u+g+s+ftype+l+sha256

    /etc Content
    !/etc/static$
    /root/\.ssh(/|$) Content
    /home/[^/]+/\.ssh(/|$) Content
    /var/lib/secrets Content
  '';

  # counts only go to ntfy, paths stay in the journal
  check = pkgs.writeShellScript "aide-check" ''
    set -uo pipefail
    PATH=${pkgs.lib.makeBinPath [ pkgs.aide pkgs.curl pkgs.gawk pkgs.coreutils ]}
    HOST=${config.networking.hostName}

    notify() {
      [ -n "''${NTFY_URL:-}" ] || return 0
      local hdr=(-H "Title: $1" -H "Priority: high" -H "Tags: rotating_light")
      [ -n "''${NTFY_TOKEN:-}" ] && hdr+=(-H "Authorization: Bearer $NTFY_TOKEN")
      curl -fsS -m ${toString facts.ntfy_timeout} "''${hdr[@]}" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
    }

    if [ ! -f /var/lib/aide/aide.db ]; then
      notify "AIDE: no baseline on $HOST" "run nixos/aide-accept.sh from ctl-0"
      exit 1
    fi

    out=$(aide --config=/etc/aide.conf --check 2>&1)
    rc=$?
    printf '%s\n' "$out"

    # exit bits 1/2/4 = added/removed/changed, 14+ = aide error
    [ "$rc" -eq 0 ] && exit 0
    if [ "$rc" -ge 14 ]; then
      notify "AIDE failed on $HOST" "exit $rc, see journalctl -u aide-check"
      exit "$rc"
    fi

    count() { awk -F: -v k="$1" '$1 ~ k { gsub(/[^0-9]/, "", $2); print $2; exit }' <<<"$out"; }
    notify "AIDE: changes on $HOST" \
      "$HOST: $(count 'Changed entries') changed, $(count 'Added entries') added, $(count 'Removed entries') removed. review + accept from ctl-0: nixos/aide-accept.sh"
    exit 0
  '';
in
{
  environment.systemPackages = [ pkgs.aide ];
  environment.etc."aide.conf".source = conf;
  systemd.tmpfiles.rules = [ "d /var/lib/aide 0700 root root -" ];

  systemd.services.aide-check = {
    description = "AIDE integrity check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = check;
      EnvironmentFile = "-/var/lib/secrets/aide/ntfy.env";   # NTFY_URL=, NTFY_TOKEN= (optional)
      Nice = checkNice;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = facts.aide_check_time;
      RandomizedDelaySec = facts.aide_check_delay;
      Persistent = true;
    };
  };
}
