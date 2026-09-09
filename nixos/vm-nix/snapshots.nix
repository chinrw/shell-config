{ ... }:
{
  # btrbk needs the pool top level to see the subvolumes side by side.
  fileSystems."/mnt/btr_pool" = {
    device = "/dev/disk/by-uuid/fcc7a60a-a40b-45c4-a463-ec8e5e3efb3a";
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "noatime"
      "compress=zstd:1"
      "discard=async"
    ];
  };

  # btrbk refuses to run if snapshot_dir is missing.
  systemd.tmpfiles.rules = [ "d /mnt/btr_pool/snapshots 0700 root root -" ];

  services.btrbk.instances.local = {
    onCalendar = "*:0/15";
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "1d";
      snapshot_preserve = "no";
      volume."/mnt/btr_pool" = {
        snapshot_dir = "snapshots";
        subvolume."@" = { };
        subvolume."@home" = { };
      };
    };
  };

  # discard=async
  services.fstrim.enable = true;
}
