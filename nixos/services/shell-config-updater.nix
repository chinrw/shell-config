{
  config,
  lib,
  pkgs,
  ...
}:
let
  serviceName = "shell-config-updater";
  serviceUser = serviceName;
  stateRoot = "/var/lib/${serviceName}";
  repoUrl = "https://github.com/chinrw/shell-config.git";
  cachixConfig = "/home/chin39/.config/cachix/cachix.dhall";
  linuxTargets = [
    ".#homeConfigurations.\"chin39@vm-nix\".activationPackage"
    ".#nixosConfigurations.vm-nix.config.system.build.toplevel"
    ".#homeConfigurations.\"chin39@work\".activationPackage"
    ".#nixosConfigurations.work-laptop.config.system.build.toplevel"
  ];

  gitAskPass = pkgs.writeShellScript "${serviceName}-askpass" ''
    case "$1" in
      *Username*)
        printf '%s\n' 'x-access-token'
        ;;
      *Password*)
        ${lib.getExe' pkgs.coreutils "cat"} "$CREDENTIALS_DIRECTORY/github-token"
        ;;
      *)
        exit 1
        ;;
    esac
  '';

  updater = pkgs.writeShellApplication {
    name = serviceName;
    runtimeInputs = [
      pkgs.cachix
      pkgs.coreutils
      pkgs.git
      pkgs.nix
    ];
    text = ''
      umask 077

      fail() {
        printf 'shell-config updater: %s\n' "$*" >&2
        exit 1
      }

      [[ -s "$CREDENTIALS_DIRECTORY/github-token" ]] \
        || fail 'GitHub credential is empty'
      [[ -s "$CREDENTIALS_DIRECTORY/cachix-config" ]] \
        || fail 'Cachix credential is empty'

      export GIT_ASKPASS=${lib.escapeShellArg gitAskPass}
      export GIT_TERMINAL_PROMPT=0

      repo_dir="$RUNTIME_DIRECTORY/repo"
      git clone --depth 1 --branch main --single-branch --no-tags \
        ${lib.escapeShellArg repoUrl} "$repo_dir"
      git -C "$repo_dir" config --local user.name 'Ruowen Qin'
      git -C "$repo_dir" config --local user.email 'chinqrw@gmail.com'

      base_revision="$(git -C "$repo_dir" rev-parse HEAD)"
      github_token="$(<"$CREDENTIALS_DIRECTORY/github-token")"
      nix_config="$(printf 'accept-flake-config = false\naccess-tokens = github.com=%s\n' "$github_token")"
      (
        cd "$repo_dir"
        NIX_CONFIG="$nix_config" nix flake update --commit-lock-file
      )
      unset github_token nix_config

      candidate_revision="$(git -C "$repo_dir" rev-parse HEAD)"
      if [[ "$candidate_revision" != "$base_revision" ]]; then
        [[ "$(git -C "$repo_dir" diff --name-only "$base_revision..$candidate_revision")" == flake.lock ]] \
          || fail 'flake update committed paths other than flake.lock'
        git -C "$repo_dir" commit --amend --no-edit --signoff
        candidate_revision="$(git -C "$repo_dir" rev-parse HEAD)"
      fi

      [[ -z "$(git -C "$repo_dir" status --porcelain=v1)" ]] \
        || fail 'flake update left a dirty checkout'

      # Avoid re-pushing an unchanged closure on every timer tick. If local GC
      # removes an output, fall through and rebuild/re-upload it.
      state_file="$STATE_DIRECTORY/last-cached"
      if [[ "$candidate_revision" == "$base_revision" && -r "$state_file" ]]; then
        mapfile -t cached <"$state_file"
        if (( ''${#cached[@]} > 1 )) && [[ "''${cached[0]}" == "$base_revision" ]]; then
          all_present=1
          for store_path in "''${cached[@]:1}"; do
            [[ -e "$store_path" ]] || { all_present=0; break; }
          done
          if (( all_present )); then
            printf 'shell-config updater: %s already cached\n' "$base_revision"
            exit 0
          fi
        fi
      fi

      store_paths_file="$RUNTIME_DIRECTORY/store-paths"
      (
        cd "$repo_dir"
        # Runtime out-links protect the outputs from GC through the Cachix
        # upload, then disappear when systemd removes RuntimeDirectory.
        NIX_CONFIG='accept-flake-config = false' nix build \
          --print-build-logs \
          --print-out-paths \
          --out-link "$RUNTIME_DIRECTORY/result" \
          --max-jobs 2 \
          --cores 8 \
          ${lib.escapeShellArgs linuxTargets}
      ) >"$store_paths_file"

      mapfile -t store_paths <"$store_paths_file"
      (( ''${#store_paths[@]} > 0 )) || fail 'Nix returned no output paths'
      cachix --config "$CREDENTIALS_DIRECTORY/cachix-config" \
        push chinrw "''${store_paths[@]}"

      if [[ "$candidate_revision" != "$base_revision" ]]; then
        # Main must never point at a lock whose paths are not yet in Cachix.
        git -C "$repo_dir" push origin HEAD:refs/heads/main
      fi

      state_file_tmp="$STATE_DIRECTORY/.last-cached.tmp"
      {
        printf '%s\n' "$candidate_revision"
        printf '%s\n' "''${store_paths[@]}"
      } >"$state_file_tmp"
      mv "$state_file_tmp" "$state_file"

      printf 'shell-config updater: cached %s\n' "$candidate_revision"
    '';
  };
in
{
  sops.secrets."shell-config-updater/github-token" = { };

  users.groups.${serviceUser} = { };
  users.users.${serviceUser} = {
    isSystemUser = true;
    description = "shell-config update service";
    group = serviceUser;
    home = stateRoot;
    createHome = false;
  };

  systemd.services.${serviceName} = {
    description = "Update and cache shell-config";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = config.networking.proxy.envVars;

    serviceConfig = {
      Type = "oneshot";
      User = serviceUser;
      Group = serviceUser;
      ExecStart = lib.getExe updater;
      StateDirectory = serviceName;
      StateDirectoryMode = "0700";
      RuntimeDirectory = serviceName;
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
      LoadCredential = [
        "github-token:${config.sops.secrets."shell-config-updater/github-token".path}"
        "cachix-config:${cachixConfig}"
      ];

      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
        "AF_UNIX"
      ];
    };
  };

  systemd.timers.${serviceName} = {
    description = "Update shell-config every three hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/3:00:00";
      Persistent = true;
      AccuracySec = "1min";
    };
  };
}
