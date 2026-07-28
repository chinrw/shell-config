{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  home = config.users.users.${username}.home;

  # The checkout you work in. The service never runs from it, but it owns the
  # .git the deployment worktree hangs off, and its data/ + .env are the runtime
  # state both share.
  userDir = "${home}/Documents/play/stocks";

  # Machine-owned deployment worktree, detached at origin/main. Nothing edits it
  # by hand, which is what lets the guards below stay strict: before this
  # existed, the service served whatever branch the checkout happened to be on.
  srvDir = "${home}/Documents/play/stocks-srv";
  branch = "main";

  endpoints = import ../../lib/stocks-endpoints.nix;

  # Create the worktree on first use and keep the shared state linked. Runs
  # before both the server and the updater, so either one provisions it.
  bootstrapScript = pkgs.writeShellApplication {
    name = "stocks-server-bootstrap";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
      pkgs.openssh
    ];
    text = ''
      if [ ! -e ${srvDir}/.git ]; then
        echo "creating the deployment worktree at ${srvDir}"
        git -C ${userDir} fetch --quiet origin
        # Detached: `${branch}` is checked out in ${userDir}, and git allows a
        # branch in one worktree only.
        git -C ${userDir} worktree add --detach ${srvDir} origin/${branch}
      fi

      # data/ and .env are the shared halves: the same database file, and one
      # place for credentials and ports. Both are gitignored, so the links never
      # make the deployment worktree look dirty.
      link() {
        if [ -e "$2" ] && [ ! -L "$2" ]; then
          echo "$2 exists and is not a symlink - refusing to replace it" >&2
          exit 1
        fi
        ln -sfn "$1" "$2"
      }
      link ${userDir}/.env ${srvDir}/.env
      link ${userDir}/data ${srvDir}/data
    '';
  };

  # Fast-forward the deployment worktree and bounce the server only when HEAD
  # moved. Every blocked state fails the unit so it shows up in
  # `systemctl --user --failed`; only transient network errors are soft skips.
  # Nobody works in this tree, so anything unexpected here is worth a red unit.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-server-update";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh # github remote is ssh; key auth works agent-less
    ];
    text = ''
      cd ${srvDir}

      if git symbolic-ref -q HEAD >/dev/null; then
        echo "deployment worktree has a branch checked out, expected detached - refusing" >&2
        exit 1
      fi
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "deployment worktree has modified tracked files - updates blocked" >&2
        exit 1
      fi

      if ! git fetch --quiet origin; then
        echo "fetch failed (network / auth?) - retrying on the next timer tick"
        exit 0
      fi

      ahead=$(git rev-list --count origin/${branch}..HEAD)
      behind=$(git rev-list --count HEAD..origin/${branch})
      if [ "$ahead" -gt 0 ]; then
        echo "deployment worktree has $ahead commit(s) origin/${branch} lacks - refusing" >&2
        exit 1
      fi
      if [ "$behind" -eq 0 ]; then
        echo "up to date with origin/${branch}"
        exit 0
      fi

      git merge --ff-only --quiet origin/${branch}
      echo "fast-forwarded $behind commit(s) -> $(git rev-parse --short HEAD), restarting stocks-server"
      # try-restart: only bounce the server if it is running; a unit the user
      # stopped stays down instead of being resurrected.
      ${pkgs.systemd}/bin/systemctl --user try-restart stocks-server.service
    '';
  };

  # These live in /etc/systemd/user, which every user manager on the box reads.
  # Only ${username} has the checkout, and without this guard a root login would
  # run the launcher as root against that user's worktree.
  onlyForUser = {
    ConditionUser = username;
  };

  # NixOS otherwise pins a minimal PATH on every unit, which would replace the
  # one the user manager exports. These ran as home-manager units inheriting
  # that manager PATH, and the launcher is built against it.
  inheritUserPath = false;
in
{
  systemd.user.services = {
    stocks-server = {
      description = "Stock Analyzer server (nix run .#server)";
      after = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      unitConfig = onlyForUser;
      enableDefaultPath = inheritUserPath;
      serviceConfig = {
        WorkingDirectory = srvDir;
        # Hosts the front accepts besides loopback, i.e. what caddy is bound to
        # in stocks-proxy.nix. Without it every proxied request is a 403. Set
        # here rather than in .env, which is shared with the checkout you work
        # in.
        Environment = "STOCKS_ALLOWED_ORIGINS=${endpoints.allowedOriginsFor endpoints.ports.stocks}";
        ExecStartPre = lib.getExe bootstrapScript;
        ExecStart = "${lib.getExe pkgs.nix} run ${srvDir}#server";
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
      description = "Fast-forward the stocks deployment worktree and restart the server on updates";
      unitConfig = onlyForUser;
      enableDefaultPath = inheritUserPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = lib.getExe bootstrapScript;
        ExecStart = lib.getExe updateScript;
      };
    };
  };

  systemd.user.timers.stocks-server-update = {
    description = "Poll the stocks upstream for updates";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyForUser;
    timerConfig = {
      OnStartupSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "1min";
    };
  };
}
