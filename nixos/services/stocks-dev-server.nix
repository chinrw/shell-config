{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  home = config.users.users.${username}.home;

  # The dev checkout you work in. Its data/ and .env are what the deployment
  # worktree below links to.
  devDir = "${home}/Documents/play/stocks-dev";

  # Machine-owned deployment worktree, detached at origin/stocks-dev. A separate
  # unit rather than a parameterisation of stocks-server.nix: the branches
  # differ and the DB sync only exists here.
  #
  # The port is not set here. The launcher resolves it from the linked .env
  # (PORT=5002) and defaults GATHER_PORT to 5106, so main (:5001/:5101) and dev
  # (:5002/:5106) do not collide.
  devSrvDir = "${home}/Documents/play/stocks-dev-srv";
  devBranch = "stocks-dev";

  endpoints = import ../../lib/stocks-endpoints.nix;

  # The main stack's database — the sync source, only ever read here.
  mainDb = "${home}/Documents/play/stocks/data/stocks.db";

  # The dev database lives in the checkout you work in; the deployment worktree
  # links to that same directory, so both stacks see one file.
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

  # Create the deployment worktree on first use and keep the shared state
  # linked. Same shape as the one in stocks-server.nix, against the dev pair.
  bootstrapScript = pkgs.writeShellApplication {
    name = "stocks-dev-bootstrap";
    runtimeInputs = [
      pkgs.git
      pkgs.coreutils
      pkgs.openssh
    ];
    text = ''
      if [ ! -e ${devSrvDir}/.git ]; then
        echo "creating the deployment worktree at ${devSrvDir}"
        git -C ${devDir} fetch --quiet origin
        git -C ${devDir} worktree add --detach ${devSrvDir} origin/${devBranch}
      fi

      link() {
        if [ -e "$2" ] && [ ! -L "$2" ]; then
          echo "$2 exists and is not a symlink - refusing to replace it" >&2
          exit 1
        fi
        ln -sfn "$1" "$2"
      }
      link ${devDir}/.env ${devSrvDir}/.env
      link ${devDir}/data ${devSrvDir}/data
    '';
  };

  # Follow origin/stocks-dev and bounce the dev server when it moves. Nobody
  # works in the deployment worktree, so blocked states fail the unit rather
  # than skipping quietly; only network errors are soft.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-dev-update";
    runtimeInputs = [
      pkgs.git
      pkgs.nix
      pkgs.openssh # github remote is ssh; key auth works agent-less
      pkgs.coreutils
    ];
    text = ''
      cd ${devSrvDir}

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
      if ! git rev-parse --verify --quiet origin/${devBranch} >/dev/null; then
        echo "origin/${devBranch} does not exist - skipping"
        exit 0
      fi

      ahead=$(git rev-list --count origin/${devBranch}..HEAD)
      behind=$(git rev-list --count HEAD..origin/${devBranch})
      if [ "$ahead" -gt 0 ]; then
        echo "deployment worktree has $ahead commit(s) origin/${devBranch} lacks - refusing" >&2
        exit 1
      fi
      if [ "$behind" -eq 0 ]; then
        echo "up to date with origin/${devBranch}"
        exit 0
      fi

      old=$(git rev-parse HEAD)
      git merge --ff-only --quiet origin/${devBranch}
      new=$(git rev-parse HEAD)
      echo "fast-forwarded $behind commit(s) -> $(git rev-parse --short HEAD), building"

      # Build before the restart; see the note in stocks-server.nix.
      changed_paths=$(git diff --name-only "$old" "$new")

      frontend_changed=false
      while IFS= read -r path; do
        case "$path" in
          crates/frontend/*|crates/shared-types/*|crates/core/*)
            frontend_changed=true
            break
            ;;
        esac
      done <<< "$changed_paths"

      if [ "$frontend_changed" = true ]; then
        if ! nix develop ${devSrvDir} --command bash -c 'cd crates/frontend && trunk build --release'; then
          echo "frontend build failed - stocks-dev-server will not be restarted" >&2
          exit 1
        fi
      fi
      if ! nix develop ${devSrvDir} --command bash -c 'cd crates && cargo build --release --manifest-path backend/Cargo.toml'; then
        echo "backend build failed - stocks-dev-server will not be restarted" >&2
        exit 1
      fi

      echo "build ok, restarting stocks-dev-server"

      # Bypass the sync throttle for this restart: upstream moving is when the
      # dev database should be re-aligned with main's.
      touch ${syncForce}
      # try-restart: only bounce the server if it is running; a unit the user
      # stopped stays down. The sync rides along as its ExecStartPre.
      ${pkgs.systemd}/bin/systemctl --user try-restart stocks-dev-server.service
    '';
  };
  # See the notes in stocks-server.nix: /etc/systemd/user is read by every user
  # manager and only ${username} has these worktrees, and the units keep the
  # manager's PATH instead of the minimal one NixOS pins by default.
  onlyForUser = {
    ConditionUser = username;
  };
  inheritUserPath = false;
in
{
  systemd.user.services = {
    stocks-dev-server = {
      description = "Stock Analyzer dev server (stocks-dev worktree, nix run .#server)";
      after = [ "network-online.target" ];
      wantedBy = [ "default.target" ];
      unitConfig = onlyForUser;
      enableDefaultPath = inheritUserPath;
      serviceConfig = {
        WorkingDirectory = devSrvDir;
        # Same allowlist as the main server, on this stack's port — see the note
        # in stocks-server.nix.
        Environment = "STOCKS_ALLOWED_ORIGINS=${endpoints.allowedOriginsFor endpoints.ports.stocks-dev}";
        # Bootstrap first: the sync writes into the linked data/, and the
        # launcher needs the worktree to exist. Then re-align the database with
        # main before every boot, so `systemctl --user restart
        # stocks-dev-server` is also how you refresh the dev data. The sync
        # soft-fails into "keep the current database".
        ExecStartPre = [
          (lib.getExe bootstrapScript)
          (lib.getExe syncScript)
        ];
        ExecStart = "${lib.getExe pkgs.nix} run ${devSrvDir}#server";
        # Same policy as the main server: retry transient build/boot failures at
        # 30s spacing. The noisy case is the launcher's port/lock pre-check
        # refusing to boot next to a hand-started dev stack on :5002 — stop that
        # instance (or this unit) to end the retry loop.
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    stocks-dev-update = {
      description = "Fast-forward the stocks-dev deployment worktree and restart the dev server on updates";
      unitConfig = onlyForUser;
      enableDefaultPath = inheritUserPath;
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = lib.getExe bootstrapScript;
        ExecStart = lib.getExe updateScript;
      };
    };
  };

  systemd.user.timers.stocks-dev-update = {
    description = "Poll the stocks-dev upstream for updates";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyForUser;
    timerConfig = {
      # 3min at startup (main polls at 2min) so the two checkouts do not fetch
      # in the same second on every boot.
      OnStartupSec = "3min";
      OnUnitActiveSec = "5min";
      AccuracySec = "1min";
    };
  };
}
