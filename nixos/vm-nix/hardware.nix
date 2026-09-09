{
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [
    "uhci_hcd"
    "ehci_pci"
    "ahci"
    "virtio_pci"
    "sr_mod"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # One btrfs on a thick LV (PVE storage asgard); grow with
  # `qm disk resize` then `btrfs filesystem resize max /`.
  fileSystems =
    let
      btrfs = subvol: {
        device = "/dev/disk/by-uuid/fcc7a60a-a40b-45c4-a463-ec8e5e3efb3a";
        fsType = "btrfs";
        options = [
          "subvol=${subvol}"
          "compress=zstd:1"
          "noatime"
          "discard=async"
        ];
      };
    in
    {
      "/" = btrfs "@";
      "/nix" = btrfs "@nix";
      # sops-nix reads age.keyFile from /home during activation, before
      # systemd mounts; keep the subvolume in initrd.
      "/home" = btrfs "@home" // {
        neededForBoot = true;
      };
      # Own subvolume so a root rollback keeps the logs of the broken period.
      "/var/log" = btrfs "@log" // {
        neededForBoot = true;
      };
      "/var/lib/docker" = btrfs "@docker";
      "/boot" = {
        device = "/dev/disk/by-uuid/A2E0-86A7";
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
        ];
      };
    };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
