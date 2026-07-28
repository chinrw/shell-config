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

  endpoints = import ../../lib/stocks-endpoints.nix;

  # Fast-forward the checkout from origin/main and bounce the server only when
  # HEAD actually moved. Looks similar to the stocks repo's scripts/git-poll.sh
  # but encodes the opposite policy on purpose — don't merge them: git-poll is
  # a dev-loop that follows any branch and swallows every error; this is
  # deployment policy — pinned to main, and every state that blocks updates
  # indefinitely (wrong branch, dirty tree, diverged history) fails the unit
  # so it shows up in `systemctl --user --failed`. Only transient network
  # errors are soft skips.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-server-update";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh # github remote is ssh; key auth works agent-less
    ];
    text = ''
      cd ${stocksDir}

      branch=$(git rev-parse --abbrev-ref HEAD)
      if [ "$branch" != "main" ]; then
        echo "checkout is on '$branch' but the deployment branch is main - refusing" >&2
        exit 1
      fi
      # --untracked-files=no: this checkout permanently carries untracked agent
      # worktrees (.codex-*wt*/) and scratch docs, and counting those as dirty
      # blocked deployment indefinitely. Modified tracked files still block. An
      # untracked file sitting where upstream adds one aborts the ff-merge
      # below, which errexit turns into a failed unit.
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "checkout has modified tracked files - updates blocked" >&2
        exit 1
      fi

      if ! git fetch --quiet origin; then
        echo "fetch failed (network / auth?) - retrying on the next timer tick"
        exit 0
      fi

      ahead=$(git rev-list --count origin/main..HEAD)
      behind=$(git rev-list --count HEAD..origin/main)
      if [ "$ahead" -gt 0 ]; then
        echo "local main has $ahead commit(s) origin/main lacks (behind $behind) - refusing to deploy" >&2
        exit 1
      fi
      if [ "$behind" -eq 0 ]; then
        echo "up to date with origin/main"
        exit 0
      fi

      git merge --ff-only --quiet origin/main
      echo "fast-forwarded $behind commit(s) -> $(git rev-parse --short HEAD), restarting stocks-server"
      # try-restart: only bounce the server if it is running; a unit the user
      # stopped stays down instead of being resurrected.
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
        # Hosts the front accepts besides loopback, i.e. what caddy is bound to
        # in stocks-proxy.nix. Without it every proxied request is a 403. Set
        # here rather than in the checkout's .env, which would dirty the tree
        # the updater above needs clean.
        Environment = "STOCKS_ALLOWED_ORIGINS=${endpoints.allowedOriginsFor endpoints.ports.stocks}";
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
