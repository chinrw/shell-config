{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.shell-config-updater;
  serviceName = "shell-config-updater";
  serviceUser = serviceName;
  stateRoot = "/var/lib/${serviceName}";
  repoUrl = "https://github.com/chinrw/shell-config.git";
  cachixConfig = cfg.cachixConfigFile;
  githubTokenFile =
    if cfg.githubTokenFile == null then
      config.sops.secrets."shell-config-updater/github-token".path
    else
      cfg.githubTokenFile;
  linuxTargets = [
    ".#nixosConfigurations.vm-nix.config.system.build.toplevel"
    ".#homeConfigurations.\"chin39@work\".activationPackage"
    ".#nixosConfigurations.work-laptop.config.system.build.toplevel"
    ".#packages.x86_64-linux.deploy-rs-ci"
    ".#checks.x86_64-linux.deploy-schema"
    ".#checks.x86_64-linux.deploy-activate"
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
      pkgs.crane
      pkgs.git
      pkgs.jq
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

      prepare_candidate() {
        local github_token nix_config
        repo_dir="$RUNTIME_DIRECTORY/repo-$1"
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

        candidate_revision="$(git -C "$repo_dir" rev-parse HEAD)"
        if [[ "$candidate_revision" != "$base_revision" ]]; then
          [[ "$(git -C "$repo_dir" diff --name-only "$base_revision..$candidate_revision")" == flake.lock ]] \
            || fail 'flake update committed paths other than flake.lock'
          git -C "$repo_dir" commit --amend --no-edit --signoff
          candidate_revision="$(git -C "$repo_dir" rev-parse HEAD)"
        fi
        ${lib.optionalString cfg.ociRefresh ''
          # A failed lookup skips the whole run, so main never mixes a new lock
          # with a stale image.
          lock="$repo_dir/lib/oci-images.json"
          # set -e ignores a failure inside a for-loop word list, so a malformed
          # lock would otherwise end the loop early and still publish.
          names="$(jq -r 'keys[]' "$lock")" || fail 'cannot read OCI image lock'
          for name in $names; do
            ref="$(jq -r --arg n "$name" '.[$n] | "\(.repository):\(.tag)"' "$lock")"
            digest="$(crane digest "$ref")" || fail "cannot resolve $ref"
            jq --arg n "$name" --arg d "$digest" '.[$n].digest = $d' "$lock" >"$lock.new"
            mv "$lock.new" "$lock"
          done
          if ! git -C "$repo_dir" diff --quiet; then
            git -C "$repo_dir" commit --quiet --signoff -m 'chore: Update OCI image digests' -- lib/oci-images.json
            candidate_revision="$(git -C "$repo_dir" rev-parse HEAD)"
          fi
        ''}

        [[ -z "$(git -C "$repo_dir" status --porcelain=v1)" ]] \
          || fail 'flake update left a dirty checkout'

        # A partial root registration must be retried even when all paths exist.
        state_file="$STATE_DIRECTORY/last-cached"
        gc_roots="$STATE_DIRECTORY/gcroots"
        if [[ "$candidate_revision" == "$base_revision" && -r "$state_file" && -f "$gc_roots/$base_revision/complete" ]]; then
          mapfile -t cached <"$state_file"
          if (( ''${#cached[@]} > 1 )) && [[ "''${cached[0]}" == "$base_revision" ]]; then
            all_present=1
            for store_path in "''${cached[@]:1}"; do
              [[ -e "$store_path" ]] || { all_present=0; break; }
            done
            if (( all_present )); then
              printf 'shell-config updater: %s already cached\n' "$base_revision"
              store_paths=( "''${cached[@]:1}" )
              return
            fi
          fi
        fi

        store_paths_file="$RUNTIME_DIRECTORY/store-paths"
        (
          cd "$repo_dir"
          NIX_CONFIG="$nix_config" nix flake archive --json --no-update-lock-file .
        ) >"$RUNTIME_DIRECTORY/sources.json"
        unset github_token nix_config
        # Every listed source is pushed to the public Cachix cache below, so
        # private inputs are dropped here.
        jq -r --argjson private ${lib.escapeShellArg (builtins.toJSON cfg.privateInputs)} \
          'reduce $private[] as $name (.; del(.inputs[$name]))
            | [.. | objects | .path? // empty] | unique[]' \
          "$RUNTIME_DIRECTORY/sources.json" >"$store_paths_file"

        # Keep the candidate alive without replacing the last successful cache.
        temporary_roots="$RUNTIME_DIRECTORY/gcroots-$1"
        mkdir -p "$temporary_roots"
        mapfile -t store_paths <"$store_paths_file"
        nix-store --realise "''${store_paths[@]}" --add-root "$temporary_roots/source" >/dev/null

        # Checks do not reference profiles in their runtime closures, so cache
        # each profile explicitly and read its target from the candidate flake.
        (
          cd "$repo_dir"
          NIX_CONFIG='accept-flake-config = false' nix eval --json .#deploy.nodes --apply '
            nodes: builtins.concatLists (builtins.attrValues (builtins.mapAttrs
              (nodeName: node: map
                (profileName: ".#deploy.nodes." + nodeName + ".profiles." + profileName + ".path")
                (builtins.attrNames node.profiles))
              nodes))
          '
        ) | jq -r '.[]' >"$RUNTIME_DIRECTORY/deploy-targets"
        mapfile -t deploy_targets <"$RUNTIME_DIRECTORY/deploy-targets"
        targets=( "''${deploy_targets[@]}" ${lib.escapeShellArgs linuxTargets} )
        index=0
        for target in "''${targets[@]}"; do
          index=$((index + 1))
          (
            cd "$repo_dir"
            # Separate clients release evaluation state between targets.
            NIX_CONFIG='accept-flake-config = false' nix build \
              --print-build-logs \
              --print-out-paths \
              --out-link "$temporary_roots/result-$index" \
              --max-jobs ${toString cfg.maxJobs} \
              --cores ${toString cfg.cores} \
              "$target"
          ) >>"$store_paths_file"
        done

        mapfile -t store_paths <"$store_paths_file"
        (( ''${#store_paths[@]} > 0 )) || fail 'Nix returned no output paths'
        ${lib.optionalString cfg.publish ''
          cachix --config "$CREDENTIALS_DIRECTORY/cachix-config" \
            push chinrw "''${store_paths[@]}"
        ''}
      }

      for attempt in 1 2 3; do
        # A conditional function call would suppress errexit inside preparation.
        prepare_candidate "$attempt"
        if ${if cfg.publish then "false" else "true"}; then
          printf 'shell-config updater: build validation passed; publishing is disabled\n'
          exit 0
        fi

        # Main must never point at a lock whose paths are not yet in Cachix.
        if [[ "$candidate_revision" != "$base_revision" ]] \
          && git -C "$repo_dir" push origin HEAD:refs/heads/main; then
          break
        fi

        git -C "$repo_dir" fetch --depth 1 origin main
        if [[ "$(git -C "$repo_dir" rev-parse FETCH_HEAD)" == "$base_revision" ]]; then
          [[ "$candidate_revision" == "$base_revision" ]] \
            || fail 'Git push failed while remote main was unchanged'
          break
        fi

        (( attempt < 3 )) || fail 'remote main changed during all 3 attempts'
        printf 'shell-config updater: remote main changed; starting attempt %s/3\n' "$((attempt + 1))"
      done

      # Root the complete published revision before releasing the previous one.
      root_generation="$gc_roots/$candidate_revision"
      mkdir -p "$root_generation"
      nix-store --realise "''${store_paths[@]}" --add-root "$root_generation/path" >/dev/null
      touch "$root_generation/complete"

      state_file_tmp="$STATE_DIRECTORY/.last-cached.tmp"
      {
        printf '%s\n' "$candidate_revision"
        printf '%s\n' "''${store_paths[@]}"
      } >"$state_file_tmp"
      mv "$state_file_tmp" "$state_file"

      for root in "$gc_roots"/*; do
        if [[ "$root" != "$root_generation" ]]; then
          rm -r -- "$root"
        fi
      done

      printf 'shell-config updater: cached %s\n' "$candidate_revision"
    '';
  };
in
{
  options.services.shell-config-updater = {
    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Runtime GitHub token file. Null uses the existing sops secret.";
    };
    cachixConfigFile = lib.mkOption {
      type = lib.types.str;
      default = "/home/chin39/.config/cachix/cachix.dhall";
      description = "Runtime Cachix configuration file loaded as a service credential.";
    };
    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Maximum number of concurrent Nix build jobs.";
    };
    cores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Number of cores advertised to each Nix build.";
    };
    ociRefresh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Refresh the digests in lib/oci-images.json from their tags and publish them with the lock update.";
    };
    privateInputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Flake inputs whose sources must not be uploaded to the public Cachix cache.";
    };
    publish = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Upload successful builds and push the updated lock file.";
    };
  };

  config = {
    sops.secrets = lib.optionalAttrs (cfg.githubTokenFile == null) {
      "shell-config-updater/github-token" = { };
    };

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
          "github-token:${githubTokenFile}"
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
  };
}
