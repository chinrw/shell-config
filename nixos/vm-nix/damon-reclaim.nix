# Give cold file cache back to the host. The host swaps this VM's RAM to make
# room for its nightly backup stream, and it cannot tell cached file pages
# from live data. A page the guest frees itself is returned through free page
# reporting at no I/O cost.
{ ... }:
{
  boot.kernelParams = [
    "damon_reclaim.enabled=Y"
    # File pages only, so anonymous memory keeps its zswap path.
    "damon_reclaim.skip_anon=Y"
    # Twenty minutes idle before a region counts as cold, so build outputs
    # survive until the link stage. DAMON_STAT shows about half of memory
    # past that mark, so the watermarks below stay reachable.
    "damon_reclaim.min_age=1200000000"
    # Per-mille of free memory. The stock 50/40/20 never engage on a guest that
    # idles at 7% free. Reclaim while free memory sits between 30% and 35%,
    # about 18 to 22 GiB for the host's backup window, and leave anything
    # below 3% to kswapd.
    "damon_reclaim.wmarks_high=350"
    "damon_reclaim.wmarks_mid=300"
    "damon_reclaim.wmarks_low=30"
  ];
}
