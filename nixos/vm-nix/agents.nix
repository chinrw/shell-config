# Coding agents (claude, codex, opencode) run whatever -j their tools pick;
# several compiling at once put the VM into oomd's kill on 2026-08-14 and
# 2026-09-04. One slice caps what all of them together may hold, entered
# through `agentsh`: everything started from that shell inherits the cgroup,
# the `claude agents` daemon and nested codex/opencode included. A zellij or
# tmux server already running outside stays outside; start a new one inside.
{ pkgs, ... }:
let
  jobs = "8";
  agentsh = pkgs.writeShellApplication {
    name = "agentsh";
    text = ''
      if [ $# -eq 0 ]; then
        set -- "''${SHELL:-/bin/sh}" -l
      fi
      # Nested call: a scope under the same slice adds nothing, run in place.
      if grep -q '/agents\.slice/' /proc/self/cgroup; then
        exec "$@"
      fi
      # Defaults only: an explicit -j or -j$(nproc) bypasses them; the slice
      # is the backstop.
      export MAKEFLAGS=-j${jobs}
      export CARGO_BUILD_JOBS=${jobs}
      export CMAKE_BUILD_PARALLEL_LEVEL=${jobs}
      export GOFLAGS=-p=${jobs}
      # systemd-run rewrites $VAR in the command line by default, which
      # breaks any argument carrying shell syntax.
      exec systemd-run --user --scope --quiet --expand-environment=no \
        --slice=agents.slice --unit="agentsh-$$" -- "$@"
    '';
  };
in
{
  systemd.user.slices.agents = {
    description = "Coding agents started through agentsh";
    sliceConfig = {
      # Past 32G resident the kernel reclaims into zswap and the Optane zvol
      # and throttles allocators. No MemoryMax on purpose: nothing in here is
      # killed (oom-guard.nix retired the oomd pressure kill for the same
      # reason); a stalled agent is the signal to raise this live with
      # `systemctl --user set-property agents.slice MemoryHigh=`.
      MemoryHigh = "32G";
      # Half of the 128G zvol; the rest stays for shells, nested qemu and
      # system.slice.
      MemorySwapMax = "64G";
    };
  };

  environment.systemPackages = [ agentsh ];
}
