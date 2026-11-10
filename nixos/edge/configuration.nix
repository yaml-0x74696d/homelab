{ facts, lib, ... }:
let
  lanPrefix = lib.last (lib.splitString "/" facts.lan_cidr);
  # the dns service ip (adr 0010) joins once pod-2 has dropped it
  holdsDnsIp = facts.dns_ip_host == "edge";
in
{
  imports = [
    ../base/time.nix
    ../base/logging.nix
    ../base/hardening.nix
    ../base/aide.nix
    ../base/fastfetch.nix
    ./traefik.nix
    ./adguard.nix
  ];

  boot.loader.grub = { enable = true; efiSupport = false; };   # disko provides the device (EF02 partition)
  boot.loader.timeout = 1;

  # proxmox virtio-scsi guest: initrd needs these to find the root disk (no hw-config generated)
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" "ahci" "xhci_pci" ];

  networking.hostName = "edge";
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # static ip, matched by the mac tofu assigns (name-agnostic)
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = lib.toLower facts.macs.edge.lan;
    address = [ "${facts.edge_ip}/${lanPrefix}" ] ++ lib.optional holdsDnsIp "${facts.dns_ip}/32";
    networkConfig = {
      Gateway = facts.gateway_ip;
      DNS = [ facts.dns_ip facts.gateway_ip ];   # dns service ip, gateway fallback
    };
  };

  # times + reboot window from schedules.yml, the rest of the upgrade is in base/hardening.nix
  system.autoUpgrade = {
    dates = facts.edge_upgrade_time;
    randomizedDelaySec = facts.edge_upgrade_delay;
    rebootWindow = facts.edge_reboot_window;
  };

  zramSwap.enable = true;   # oom cushion, no disk swap; the upgrade builds on 1.5G

  # set to the release you first install; don't bump casually
  system.stateVersion = "26.05";
}
