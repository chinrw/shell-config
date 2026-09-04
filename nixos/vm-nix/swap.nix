# Disk swap for the 2026-08-14 balloon/zram deadlock: balloon wanted 35.7 GiB
# while zram's pool held 31.6 GiB of un-reclaimable RAM. zram compresses in
# place; only a block device frees page frames the host can take back.
{ ... }:
{
  swapDevices = [
    {
      # NixOS only mkswaps swapfiles and encrypted devices. Initialise once:
      label = "vm-nix-swap-opt";

      # Below zram (5), which is capped at 32 GiB, so this is an overflow tier.
      priority = 0;

      # Per-page discard too: the zvol shares the Optane special vdev with the
      # pool's metadata, so freed slots must go back to it, not sit allocated.
      discardPolicy = "both";
    }
  ];

  # virtio-blk carries no rotational hint, so the kernel treats vd* as spinning
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/rotational}="0"
  '';
}
