# Swap on a block device, not a compressed-in-RAM tier: only block-backed swap
# frees page frames the host can take back (balloon deadlock, 2026-08-14).
{ ... }:
{
  swapDevices = [
    {
      # NixOS only mkswaps swapfiles and encrypted devices. Initialise once:
      #   mkswap -L vm-nix-swap-opt /dev/vda
      # Label, not /dev/vda: virtio names follow PCI order and can shift.
      label = "vm-nix-swap-opt";

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
