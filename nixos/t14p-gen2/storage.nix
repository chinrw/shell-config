{ ... }:
let
  btrfsDevice = "/dev/mapper/cryptroot";
  btrfsOptions = [
    "compress=zstd:3"
    "noatime"
  ];
in
{
  boot = {
    initrd.luks.devices.cryptroot.device = "/dev/disk/by-partlabel/nixos-luks";

    kernelParams = [
      "zswap.enabled=1"
      "zswap.compressor=zstd"
      "zswap.zpool=zsmalloc"
      "zswap.max_pool_percent=20"
      "zswap.shrinker_enabled=1"
    ];
  };

  fileSystems = {
    "/" = {
      device = btrfsDevice;
      fsType = "btrfs";
      options = [ "subvol=@root" ] ++ btrfsOptions;
    };

    "/home" = {
      device = btrfsDevice;
      fsType = "btrfs";
      options = [ "subvol=@home" ] ++ btrfsOptions;
    };

    "/nix" = {
      device = btrfsDevice;
      fsType = "btrfs";
      options = [ "subvol=@nix" ] ++ btrfsOptions;
    };

    "/var/log" = {
      device = btrfsDevice;
      fsType = "btrfs";
      options = [ "subvol=@log" ] ++ btrfsOptions;
    };

    "/swap" = {
      device = btrfsDevice;
      fsType = "btrfs";
      options = [
        "subvol=@swap"
        "noatime"
      ];
    };

    "/boot" = {
      device = "/dev/disk/by-partlabel/ESP";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  };

  swapDevices = [ { device = "/swap/swapfile"; } ];
}
