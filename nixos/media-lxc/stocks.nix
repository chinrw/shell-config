{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  home = config.users.users.${username}.home;
  group = config.users.users.${username}.group;

  # The deployment clone and its state. Nobody works in this tree, which is
  # what lets the updater treat anything unexpected in it as an error.
  root = "${home}/stocks";
  srvDir = "${root}/srv";
  # The backend requires the database's parent directory to be owned by the
  # service user and closed to everyone else, so it cannot live on /mnt/data.
  dataDir = "${root}/data";
  # Revision the running server was built from, and the revision whose build
  # last failed. Kept outside the clone so neither shows up in `git status`.
  deployedStamp = "${root}/deployed-rev";
  failedStamp = "${root}/failed-rev";

  branch = "main";
  repoUrl = "git@github.com:chinrw/stocks.git";

  # web.nix serves this name through caddy. The backend answers 403 to any
  # Host that is not loopback or an exact entry of STOCKS_ALLOWED_ORIGINS.
  origin = "https://stocks.home.midashood.top";
  port = 5002;

  # A failed build is retried after this long rather than on every 5-minute
  # tick: each attempt is minutes of CPU on the host that serves the LAN's DNS.
  retryFailedBuildMinutes = 60;

  # ssh-over-proxy has stalled after connect with no error and no timeout of
  # its own, which wedged the old updater for 3 days (2026-08-14).
  gitSshCommand = lib.concatStringsSep " " [
    "ssh"
    "-i ${config.sops.secrets.stocks-deploy-key.path}"
    "-o IdentitiesOnly=yes"
    "-o BatchMode=yes"
    "-o ConnectTimeout=15"
    "-o ServerAliveInterval=10"
    "-o ServerAliveCountMax=3"
  ];

  # The launcher, uv, pnpm and the AI CLIs reach PyPI, npm and the model APIs
  # through the LAN proxy, as they did under the old user manager.
  environment = config.networking.proxy.envVars // {
    GIT_SSH_COMMAND = gitSshCommand;
  };

  # nix runs the app's own launchers; claude and codex come from the user's
  # Home Manager profile, which the gather service finds on PATH.
  path = [
    config.nix.package
    pkgs.git
    pkgs.openssh
    "${home}/.nix-profile"
  ];

  bootstrapScript = pkgs.writeShellApplication {
    name = "stocks-bootstrap";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.coreutils
      pkgs.util-linux # flock
    ];
    text = ''
      # The server and the updater both run this at boot.
      exec 9>${root}/.bootstrap.lock
      flock 9
      if [ -e ${srvDir}/.git ]; then
        exit 0
      fi
      # Clone beside the target and move it into place, so an interrupted
      # clone is retried instead of being mistaken for a deployment.
      rm -rf ${srvDir}.partial
      git clone --quiet --no-checkout ${repoUrl} ${srvDir}.partial
      git -C ${srvDir}.partial checkout --quiet --detach origin/${branch}
      mv ${srvDir}.partial ${srvDir}
      # The server's first start builds this revision itself, so the updater
      # only has to act once origin moves past it.
      git -C ${srvDir} rev-parse HEAD >${deployedStamp}
      echo "cloned ${repoUrl} at $(git -C ${srvDir} rev-parse --short HEAD)"
    '';
  };

  # Build the newest origin/main while the old server keeps serving, then ask
  # for a restart. `nix run .#build` compiles in the same environment as
  # `nix run .#server`, so the restart reuses the build instead of redoing it.
  updateScript = pkgs.writeShellApplication {
    name = "stocks-update";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.coreutils
      pkgs.findutils
      config.nix.package
    ];
    text = ''
      cd ${srvDir}

      if git symbolic-ref -q HEAD >/dev/null; then
        echo "deployment clone has a branch checked out, expected detached - refusing" >&2
        exit 1
      fi
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "deployment clone has modified tracked files - refusing" >&2
        exit 1
      fi

      if ! timeout --kill-after=10s 120s git fetch --quiet origin ${branch}; then
        echo "fetch failed or timed out - retrying on the next timer tick"
        exit 0
      fi

      target=$(git rev-parse "origin/${branch}^{commit}")
      deployed=$(cat ${deployedStamp} 2>/dev/null || true)
      if [ "$target" = "$deployed" ]; then
        echo "up to date at ''${target:0:8}"
        exit 0
      fi
      if [ "$target" = "$(cat ${failedStamp} 2>/dev/null || true)" ] \
        && [ -n "$(find ${failedStamp} -mmin -${toString retryFailedBuildMinutes})" ]; then
        echo "the build of ''${target:0:8} failed recently - waiting before the next attempt"
        exit 0
      fi

      git checkout --quiet --detach "$target"
      echo "building ''${target:0:8}"
      if ! nix run ${srvDir}#build; then
        echo "$target" >${failedStamp}
        # Go back to the running revision, so a restart for any other reason
        # does not boot into the revision that failed to build.
        if [ -n "$deployed" ]; then
          git checkout --quiet --detach "$deployed"
        fi
        echo "build of ''${target:0:8} failed - stocks-server keeps the previous build" >&2
        exit 1
      fi

      rm -f ${failedStamp}
      echo "$target" >${deployedStamp}
      touch "$RUNTIME_DIRECTORY/restart"
      echo "build ok, restarting stocks-server"
    '';
  };

  # The updater runs as ${username}, which cannot restart a system unit, so
  # this privileged step does it when the updater left the marker.
  restartScript = pkgs.writeShellScript "stocks-restart-if-built" ''
    if [ -e "$RUNTIME_DIRECTORY/restart" ]; then
      exec ${pkgs.systemd}/bin/systemctl try-restart stocks-server.service
    fi
  '';
in
{
  sops.secrets.stocks-deploy-key = {
    sopsFile = ../../secrets/stocks-deploy-key;
    format = "binary";
    owner = username;
    mode = "0400";
  };

  # CLAUDE_CODE_OAUTH_TOKEN from `claude setup-token`. It lasts a year and
  # does not refresh, unlike a /login session that would be stored in ~/.claude.
  sops.secrets.stocks-environment = {
    sopsFile = ../../secrets/stocks.env;
    format = "dotenv";
    key = "";
    mode = "0400";
    restartUnits = [ "stocks-server.service" ];
  };

  systemd.tmpfiles.rules = [
    "d ${root} 0700 ${username} ${group} -"
    "d ${dataDir} 0700 ${username} ${group} -"
  ];

  systemd.services.stocks-server = {
    description = "Stock Analyzer server (nix run .#server)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    inherit path;
    environment = environment // {
      PORT = toString port;
      GATHER_PORT = "5106";
      STOCKS_DB_PATH = "${dataDir}/stocks.db";
      STOCKS_ALLOWED_ORIGINS = origin;
      PROXY = config.networking.proxy.default;
      ANALYZER_ENGINE = "claude_cli";
      # Subscription mode blanks ANTHROPIC_API_KEY for the Claude CLI, which
      # would otherwise outrank CLAUDE_CODE_OAUTH_TOKEN.
      ANALYZER_CLI_USE_SUBSCRIPTION = "true";
      ANALYZER_CLI_MAX_TURNS = "30";
      ANALYZER_CLI_MAX_PARALLEL_AGENTS = "3";
    };
    serviceConfig = {
      User = username;
      Group = group;
      # "-": the clone does not exist until ExecStartPre has run once.
      WorkingDirectory = "-${srvDir}";
      EnvironmentFile = config.sops.secrets.stocks-environment.path;
      ExecStartPre = lib.getExe bootstrapScript;
      ExecStart = "${lib.getExe config.nix.package} run ${srvDir}#server";
      Restart = "on-failure";
      RestartSec = "30s";
      # This host also serves the LAN's DNS and proxy. Parallel AI CLI runs
      # are the largest consumer, so cap the stack rather than the host.
      MemoryHigh = "5G";
      MemoryMax = "6G";
      CPUWeight = 50;
    };
  };

  systemd.services.stocks-update = {
    description = "Build the newest stocks origin/main and restart the server";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    inherit environment path;
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = group;
      RuntimeDirectory = "stocks-update";
      ExecStartPre = lib.getExe bootstrapScript;
      ExecStart = lib.getExe updateScript;
      ExecStartPost = "+${restartScript}";
      # A cold release build must fit; the bound matters, not the value.
      TimeoutStartSec = "60min";
      Nice = 15;
      CPUWeight = 20;
      IOWeight = 20;
      MemoryMax = "6G";
    };
  };

  systemd.timers.stocks-update = {
    description = "Poll stocks origin/main for updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
      AccuracySec = "1min";
    };
  };
}
