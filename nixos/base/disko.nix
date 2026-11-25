# legacy-bios layout (seabios like the rest of the fleet, no efi disk in tofu).
# /dev/sda = the virtio-scsi disk, nixos-anywhere wipes + formats the debian bootstrap disk with it
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
