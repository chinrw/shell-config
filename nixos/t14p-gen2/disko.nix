{ inputs, ... }:
let
  btrfsOptions = [
    "compress=zstd:3"
    "noatime"
  ];
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  # Source of truth for the on-disk layout. disko derives fileSystems,
  # boot.initrd.luks.devices and swapDevices from this, so storage.nix only
  # carries tuning that has no partition equivalent.
  disko.devices.disk.main = {
    type = "disk";

    # Placeholder. Installs pass the real disk:
    #   disko-install --flake .#work-laptop --disk main /dev/disk/by-id/nvme-...
    # Nothing reads it after the install: every generated mount goes through
    # /dev/disk/by-partlabel/* or /dev/mapper/cryptroot.
    device = "/dev/disk/by-id/CHANGE-ME";

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          priority = 1;
          # Pinned: disko would default to "disk-main-ESP", which the already
          # installed machine does not have.
          label = "ESP";
          size = "1G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "fmask=0077"
              "dmask=0077"
            ];
          };
        };

        luks = {
          # Pinned for the same reason as ESP above.
          label = "nixos-luks";
          size = "100%";

          content = {
            type = "luks";
            name = "cryptroot";
            # Prompt once during format, reuse the same passphrase to open.
            askPassword = true;

            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];

              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOptions;
                };

                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOptions;
                };

                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOptions;
                };

                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = btrfsOptions;
                };

                # No compress=: `btrfs filesystem mkswapfile` needs the swapfile
                # NOCOW, and a compressed subvolume defeats that.
                "@swap" = {
                  mountpoint = "/swap";
                  mountOptions = [ "noatime" ];
                  swap.swapfile.size = "32G";
                };
              };
            };
          };
        };
      };
    };
  };
}
