# host hardening for the wan-facing netbird box. service-specific systemd
# sandboxing + firewall ports live in netbird.nix (merged into the firewall lists).
{ facts, ... }:
let
  # the controller's public key (deploys + admin login). placeholder, set yours
  adminKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA_CHANGE_ME admin@controller" ];
  sshLoginGraceTime = 30;   # seconds

  f2bMaxRetry = 3;
  f2bBantime = "1h";

  # private repo needs a fetch token
  upgradeFlake = "git+https://git.${facts.domain}/${facts.admin_user}/homelab?dir=nixos#netbird";
  upgradeAt = "04:00";
  upgradeJitter = "45min";
  rebootWindow = { lower = "03:00"; upper = "05:00"; };
  gcDates = "weekly";
  gcKeep = "30d";

  journalMax = "200M";
in
{
  # --- accounts: declarative only, no passwords ---
  users.mutableUsers = false;
  # deploy key: nixos-rebuild --target-host root@<netbird_ip> (ssh is lan-only, see firewall)
  users.users.root.openssh.authorizedKeys.keys = adminKeys;
  users.users.${facts.admin_user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = adminKeys;
  };
  security.sudo.execWheelOnly = true;

  # --- ssh: key-only, modern crypto, never wan-forwarded ---
  services.openssh = {
    enable = true;
    ports = [ facts.ssh_port ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";   # key-only, for deploys
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      MaxAuthTries = facts.ssh_max_auth_tries;
      LoginGraceTime = sshLoginGraceTime;
      Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" ];
      KexAlgorithms = [ "sntrup761x25519-sha512@openssh.com" "curve25519-sha256" "curve25519-sha256@libssh.org" ];
      Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" ];
    };
  };

  # --- firewall: default-deny, nftables. ssh restricted to lan; ---
  # --- netbird.nix opens only the control-plane ports to the world ---
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowPing = true;
    logRefusedConnections = false;   # wan scan noise
    extraInputRules = ''
      ip saddr ${facts.lan_cidr} tcp dport ${toString facts.ssh_port} accept
    '';
  };

  # --- kernel hardening ---
  boot.kernelParams = [
    "slab_nomerge"
    "init_on_alloc=1"
    "init_on_free=1"
    "page_alloc.shuffle=1"
    "randomize_kstack_offset=on"
    "debugfs=off"
  ];
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.yama.ptrace_scope" = 2;
    "kernel.kexec_load_disabled" = 1;   # after install; nixos-rebuild doesn't kexec
    "kernel.sysrq" = 0;
    "kernel.perf_event_paranoid" = 3;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;      # loosen to 2 if this box ever becomes a routing peer
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.suid_dumpable" = 0;
  };

  # --- mac + audit + brute-force ---
  security.apparmor.enable = true;
  security.auditd.enable = true;
  security.audit.enable = true;
  services.fail2ban = {
    enable = true;
    maxretry = f2bMaxRetry;
    bantime = f2bBantime;
    bantime-increment.enable = true;
  };

  # --- self-patching: security-critical for a wan box. reboots off-hours ---
  system.autoUpgrade = {
    enable = true;
    flake = upgradeFlake;
    flags = [ "--update-input" "nixpkgs" "--no-write-lock-file" ];
    dates = upgradeAt;
    randomizedDelaySec = upgradeJitter;
    allowReboot = true;
    inherit rebootWindow;
  };
  nix.gc = { automatic = true; dates = gcDates; options = "--delete-older-than ${gcKeep}"; };
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
  };

  # --- trim the surface ---
  documentation.enable = false;
  programs.command-not-found.enable = false;
  services.journald.settings.Journal.SystemMaxUse = journalMax;
  services.qemuGuest.enable = true;   # clean shutdown + proxmox visibility
  time.timeZone = facts.timezone;
  i18n.defaultLocale = "en_US.UTF-8";
}
