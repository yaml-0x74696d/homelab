# legacy-bios layout (seabios, matches the rest of the fleet — no ovmf/efi disk in tofu).
# /dev/sda = the virtio-scsi disk. nixos-anywhere runs this to wipe + format the
# debian bootstrap disk on first install.
{
  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1M"; type = "EF02"; };   # grub bios-boot partition
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };
}
