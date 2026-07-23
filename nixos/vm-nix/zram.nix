# zram swap for the 2026-07-23 memory exhaustion (~66 GiB anon, no swap,
# ~90 min of file-page thrash). Needs CONFIG_ZRAM +
# CONFIG_ZRAM_BACKEND_ZSTD in kernel.config.
{ ... }:
{
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # 64 GiB uncompressed capacity; ~21 GiB RAM when full at ~3:1.
    memoryPercent = 100;
    memoryMax = 64 * 1024 * 1024 * 1024;
  };

  boot.kernel.sysctl = {
    # Swap anon to zram instead of dropping file pages that must be
    # re-read from disk.
    "vm.swappiness" = 180;
    # No swap-in readahead; zram has no seek cost.
    "vm.page-cluster" = 0;
    # Wider watermark steps (1.25% of zone): kswapd starts earlier,
    # atomic allocations keep headroom.
    "vm.watermark_scale_factor" = 125;
    # Boost reclaim may only evict file pages and raises the min
    # watermark (pegged at its +303 MiB cap during the incident); off.
    "vm.watermark_boost_factor" = 0;
    # Against the order-5 GFP_ATOMIC failures: proactive compaction,
    # keep pageblock migratetypes pure.
    "vm.compaction_proactiveness" = 40;
    "vm.defrag_mode" = 1;
  };
}
