{ facts, lib, ... }:
let
  lanPrefix = lib.last (lib.splitString "/" facts.lan_cidr);
in
{
  imports = [ ../base/time.nix ../base/logging.nix ./hardening.nix ./aide.nix ./netbird.nix ./fastfetch.nix ];

  boot.loader.grub = { enable = true; efiSupport = false; };   # disko provides the device (EF02 partition)
  boot.loader.timeout = 1;

  # proxmox virtio-scsi guest: initrd needs these to find the root disk (no hw-config generated)
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" "ahci" "xhci_pci" ];

  networking.hostName = "netbird";
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # static ip, matched by the mac tofu assigns (name-agnostic)
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = lib.toLower facts.macs.netbird.lan;
    address = [ "${facts.netbird_ip}/${lanPrefix}" ];
    networkConfig = {
      Gateway = facts.gateway_ip;
      DNS = [ facts.dns_ip facts.gateway_ip ];   # pihole (dns service ip), gateway fallback
    };
  };

  zramSwap.enable = true;   # oom cushion, no disk swap

  # set to the release you first install; don't bump casually
  system.stateVersion = "25.05";
}
