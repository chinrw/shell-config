{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The stocks checkout this service boots. `nix run <dir>#server` resolves the
  # launcher from this worktree, and the launcher itself rebuilds the frontend
  # bundle + release backend when sources changed — so "pull then restart the
  # unit" IS the rebuild; nothing else needs to compile here.
  stocksDir = "${config.home.homeDirectory}/Documents/play/stocks";

  # Fast-forward the checkout from its upstream and bounce the server only
  # when HEAD actually moved. Same safety rails as the repo's own
  # scripts/git-poll.sh: require an upstream, require a clean tree, never
  # merge/rebase — a diverged branch is logged and left alone.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-server-update";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh # github remote is ssh; key auth works agent-less
    ];
    text = ''
      cd ${stocksDir}

      if ! upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
        echo "no upstream for $(git rev-parse --abbrev-ref HEAD) - skip"
        exit 0
      fi
      if ! git diff-index --quiet HEAD --; then
        echo "working tree dirty - skip"
        exit 0
      fi

      # Transient fetch failures (network blip) are logged and swallowed;
      # the next timer tick retries.
      if ! git fetch --quiet origin; then
        echo "fetch failed (network / auth?) - skip"
        exit 0
      fi

      behind=$(git rev-list --count "HEAD..$upstream")
      ahead=$(git rev-list --count "$upstream..HEAD")
      if [ "$behind" -eq 0 ]; then
        echo "up to date with $upstream"
        exit 0
      fi
      if [ "$ahead" -gt 0 ]; then
        echo "diverged from $upstream (ahead $ahead, behind $behind) - no action"
        exit 0
      fi

      git pull --ff-only --quiet
      echo "pulled $behind commits -> $(git rev-parse --short HEAD), restarting stocks-server"
      # try-restart: only bounce the server if it is running; a unit the user
      # stopped (or that gave up) stays down instead of being resurrected.
      ${pkgs.systemd}/bin/systemctl --user try-restart stocks-server.service
    '';
  };
in
{
  systemd.user.services = {
    stocks-server = {
      Unit = {
        Description = "Stock Analyzer server (nix run .#server)";
        After = "network-online.target";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        WorkingDirectory = stocksDir;
        ExecStart = "${lib.getExe pkgs.nix} run ${stocksDir}#server";
        # on-failure with 30s spacing retries indefinitely (never trips the
        # default start-rate limit). Deliberate: transient build/boot failures
        # self-heal. The one noisy case is the launcher's own lock/port
        # pre-check refusing to boot next to a manually started instance —
        # stop that instance (or this unit) to end the retry loop.
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    stocks-server-update = {
      Unit = {
        Description = "Fast-forward the stocks checkout and restart the server on upstream updates";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe updateScript;
      };
    };
  };

  systemd.user.timers = {
    stocks-server-update = {
      Unit = {
        Description = "Poll the stocks upstream for updates";
      };
      Timer = {
        OnStartupSec = "2min";
        OnUnitActiveSec = "5min";
        AccuracySec = "1min";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
