# zswap over the zvol in swap.nix. A zram pool would pin RAM the host cannot
# reclaim; zswap's pool stops at 20% of RAM and cold pages are written back.
{ ... }:
{
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.compressor=zstd"
    "zswap.max_pool_percent=20"
    # Reclaim cold compressed pages before the pool reaches its size limit.
    "zswap.shrinker_enabled=1"
  ];

  boot.kernel.sysctl = {
    # Swap anon through zswap instead of dropping file pages that must be
    # re-read from disk.
    "vm.swappiness" = 180;
    # Optane has no seek cost; avoid reading neighbouring cold swap pages.
    "vm.page-cluster" = 0;
    # Wider watermark steps (1.25% of zone): kswapd starts earlier,
    # atomic allocations keep headroom.
    "vm.watermark_scale_factor" = 125;
    # Boost reclaim may only evict file pages and raises the min
    # watermark (pegged at its +303 MiB cap on 2026-07-23); off.
    "vm.watermark_boost_factor" = 0;
    # Against the order-5 GFP_ATOMIC failures: proactive compaction,
    # keep pageblock migratetypes pure.
    "vm.compaction_proactiveness" = 40;
    "vm.defrag_mode" = 1;
  };
}
