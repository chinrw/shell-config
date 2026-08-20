{ ... }:
{
  # Partitions, mounts, LUKS and the swapfile come from ./disko.nix.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
    "zswap.max_pool_percent=20"
    "zswap.shrinker_enabled=1"
  ];
}
