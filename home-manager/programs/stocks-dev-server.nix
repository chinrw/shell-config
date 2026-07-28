{
  config,
  lib,
  pkgs,
  ...
}:

let
  # The stocks-dev worktree — a git worktree of the stocks checkout, pinned to
  # the `stocks-dev` branch. A separate unit rather than a parameterisation of
  # stocks-server.nix: main is a deployment that must not drift, this is a dev
  # checkout that is allowed to be dirty, and the DB sync only exists here.
  #
  # The port is not set here. The launcher resolves it from this worktree's own
  # .env (PORT=5002, also in the repo's PORT_MAP) and defaults GATHER_PORT to
  # 5106, so main (:5001/:5101) and dev (:5002/:5106) do not collide.
  devDir = "${config.home.homeDirectory}/Documents/play/stocks-dev";
  devBranch = "stocks-dev";

  endpoints = import ../../lib/stocks-endpoints.nix;

  # The deployment checkout's database — the sync source, only ever read here.
  mainDb = "${config.home.homeDirectory}/Documents/play/stocks/data/stocks.db";

  devDb = "${devDir}/data/stocks.db";
  # data/ is gitignored, so this bookkeeping never shows up in `git status`.
  syncStamp = "${devDir}/data/.main-sync-stamp";
  syncForce = "${devDir}/data/.main-sync-force";
  syncPartial = "${devDir}/data/.main-sync.partial";

  # Floor between two automatic syncs. The sync is the server's ExecStartPre and
  # the server retries every 30s while it fails to boot, so without a floor a
  # crash loop would VACUUM ~200 MB out of the live main database twice a
  # minute. A pull that moved HEAD drops the force marker to bypass it.
  syncMinIntervalSec = 600;

  # Replace the dev database with a copy of main's. Every failure is a skip that
  # keeps the current dev database: this runs as ExecStartPre, so a failed copy
  # must not stop the server from booting. Each skip logs its reason.
  syncScript = pkgs.writeShellApplication {
    name = "stocks-dev-db-sync";
    runtimeInputs = [
      pkgs.sqlite
      pkgs.coreutils
      pkgs.psmisc # fuser
    ];
    text = ''
      if [ ! -f ${mainDb} ]; then
        echo "no main database at ${mainDb} - keeping the dev database as is" >&2
        exit 0
      fi

      now=$(date +%s)
      if [ -e ${syncForce} ]; then
        rm -f ${syncForce}
      elif [ -f ${syncStamp} ]; then
        age=$((now - $(stat -c %Y ${syncStamp})))
        if [ "$age" -lt ${toString syncMinIntervalSec} ]; then
          echo "last sync ''${age}s ago (< ${toString syncMinIntervalSec}s) - skipping"
          exit 0
        fi
      fi

      # Never swap the file out from under a live connection: the dev stack is
      # also started by hand (`nix run .#server`), and replacing it while SQLite
      # holds the old inode loses that instance's writes. The unit's own
      # ExecStart cannot be the holder, ExecStartPre runs first.
      if fuser -s ${devDb} ${devDb}-wal 2>/dev/null; then
        echo "dev database is open by another process (hand-started stack?) - skipping sync" >&2
        exit 0
      fi

      rm -f ${syncPartial}
      # VACUUM INTO, not cp: reads inside a transaction (safe while the main
      # server writes), folds in the -wal, lands compacted. Same primitive as
      # the app's own startup backup. `PRAGMA busy_timeout` echoes its value, so
      # stdout is dropped; a real failure still lands on stderr.
      if ! sqlite3 ${mainDb} "PRAGMA busy_timeout=10000; VACUUM INTO '${syncPartial}'" >/dev/null; then
        echo "VACUUM INTO failed (main database busy?) - keeping the dev database as is" >&2
        rm -f ${syncPartial}
        exit 0
      fi

      if [ -f ${devDb} ]; then
        # Fold the outgoing -wal back in so the backup is a complete file even
        # if the previous dev server was killed rather than stopped. Nobody
        # holds the DB (checked above), so this cannot block.
        if ! sqlite3 ${devDb} 'PRAGMA busy_timeout=5000; PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null; then
          echo "checkpoint of the outgoing dev database failed - backing it up anyway" >&2
        fi
        # Hardlink, not copy: the rename below retires the old database, and
        # this keeps its inode under one rolling backup name.
        ln -f ${devDb} ${devDb}.bak-pre-maincopy
      fi

      # -wal/-shm belong to the outgoing inode; leaving them next to the new
      # file would hand SQLite a WAL from a different database.
      rm -f ${devDb}-wal ${devDb}-shm
      mv -f ${syncPartial} ${devDb}
      # Match the 0600 the rest of data/ carries; VACUUM INTO honours umask.
      chmod 600 ${devDb}
      touch ${syncStamp}
      echo "dev database synced from main ($(stat -c %s ${devDb}) bytes)"
    '';
  };

  # Follow origin/stocks-dev and bounce the dev server when it moves. Unlike
  # stocks-server-update, every blocked state is a logged skip that leaves the
  # unit successful — this worktree is where development happens, so "cannot
  # update right now" is the normal case, not a fault.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-dev-update";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh # github remote is ssh; key auth works agent-less
      pkgs.coreutils
    ];
    text = ''
      cd ${devDir}

      branch=$(git rev-parse --abbrev-ref HEAD)
      if [ "$branch" != "${devBranch}" ]; then
        echo "checkout is on '$branch', not ${devBranch} - skipping"
        exit 0
      fi

      # --untracked-files=no: agent worktrees, scratch docs and build leftovers
      # live untracked here permanently; only edits to tracked files block.
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "tracked files are modified - skipping"
        exit 0
      fi

      if ! git fetch --quiet origin; then
        echo "fetch failed (network / auth?) - retrying on the next timer tick"
        exit 0
      fi
      if ! git rev-parse --verify --quiet origin/${devBranch} >/dev/null; then
        echo "origin/${devBranch} does not exist - skipping"
        exit 0
      fi

      ahead=$(git rev-list --count origin/${devBranch}..HEAD)
      behind=$(git rev-list --count HEAD..origin/${devBranch})
      if [ "$ahead" -gt 0 ]; then
        echo "local ${devBranch} is $ahead commit(s) ahead (behind $behind) - skipping"
        exit 0
      fi
      if [ "$behind" -eq 0 ]; then
        echo "up to date with origin/${devBranch}"
        exit 0
      fi

      if ! git merge --ff-only --quiet origin/${devBranch}; then
        echo "ff-merge failed (untracked file in the way?) - skipping" >&2
        exit 0
      fi
      echo "fast-forwarded $behind commit(s) -> $(git rev-parse --short HEAD), restarting stocks-dev-server"

      # Bypass the sync throttle for this restart: upstream moving is when the
      # dev database should be re-aligned with main's.
      touch ${syncForce}
      # try-restart: only bounce the server if it is running; a unit the user
      # stopped stays down. The sync rides along as its ExecStartPre.
      ${pkgs.systemd}/bin/systemctl --user try-restart stocks-dev-server.service
    '';
  };
in
{
  systemd.user.services = {
    stocks-dev-server = {
      Unit = {
        Description = "Stock Analyzer dev server (stocks-dev worktree, nix run .#server)";
        After = "network-online.target";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        WorkingDirectory = devDir;
        # Same allowlist as the main server, on this worktree's port — see the
        # note in stocks-server.nix.
        Environment = "STOCKS_ALLOWED_ORIGINS=${endpoints.allowedOriginsFor endpoints.ports.stocks-dev}";
        # Re-align the database with main before every boot, so `systemctl
        # --user restart stocks-dev-server` is also how you refresh the dev
        # data. Soft-fails into "keep the current database".
        ExecStartPre = lib.getExe syncScript;
        ExecStart = "${lib.getExe pkgs.nix} run ${devDir}#server";
        # Same policy as the main server: retry transient build/boot failures at
        # 30s spacing. The noisy case is the launcher's port/lock pre-check
        # refusing to boot next to a hand-started dev stack on :5002 — stop that
        # instance (or this unit) to end the retry loop.
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    stocks-dev-update = {
      Unit = {
        Description = "Fast-forward the stocks-dev worktree and restart the dev server on updates";
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe updateScript;
      };
    };
  };

  systemd.user.timers = {
    stocks-dev-update = {
      Unit = {
        Description = "Poll the stocks-dev upstream for updates";
      };
      Timer = {
        # 3min at startup (main polls at 2min) so the two checkouts do not fetch
        # in the same second on every boot.
        OnStartupSec = "3min";
        OnUnitActiveSec = "5min";
        AccuracySec = "1min";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
