# Disk swap for the 2026-08-14 balloon/zram deadlock: balloon wanted 35.7 GiB
# while zram's pool held 31.6 GiB of un-reclaimable RAM. zram compresses in
# place; only a block device frees page frames the host can take back.
{ ... }:
{
  swapDevices = [
    {
      # NixOS only mkswaps swapfiles and encrypted devices. Initialise once:
      #   mkswap -L vm-nix-swap /dev/vdb
      # Label, not /dev/vdb: virtio names follow PCI order and can shift.
      label = "vm-nix-swap";

      # Below zram (5), which stays at 64 GiB, so this is an overflow tier.
      priority = 0;

      # One bulk discard at swapon; no per-page discard during reclaim.
      discardPolicy = "once";
    }
  ];
}
