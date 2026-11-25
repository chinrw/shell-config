{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
  home = config.home.homeDirectory;
  xdgConfig = config.xdg.configHome;
  sharedAgentInstructions = import ./agent-instructions { inherit lib pkgs; };

  cliSettingsBase = {
    # Use explicit read_file(*) + deny rules instead of allowNonWorkspaceAccess
    # so out-of-workspace writes stay gated while non-sensitive reads proceed.
    allowNonWorkspaceAccess = false;
    permissions = {
      allow = [
        "read_file(*)"
      ];
      deny = [
        "read_file(.env)"
        "read_file(.env.local)"
        "read_file(.env.production)"
        "read_file(.env.development)"
        "read_file(.env.staging)"
        "read_file(.env.secret)"
        "read_file(${home}/.ssh)"
        "read_file(${home}/.gnupg)"
        "read_file(${xdgConfig}/sops)"
        "read_file(${xdgConfig}/sops-nix)"
        "read_file(${xdgConfig}/op)"
        "read_file(${home}/.aws)"
        "read_file(${home}/.kube)"
        "read_file(${home}/.docker/config.json)"
        "read_file(${xdgConfig}/gh/hosts.yml)"
        "read_file(${xdgConfig}/rclone)"
        "read_file(${xdgConfig}/cachix/cachix.dhall)"
        "read_file(${home}/.git-credentials)"
        "read_file(${home}/.netrc)"
        "read_file(${home}/.npmrc)"
        "read_file(${home}/.pypirc)"
        "read_file(${home}/.dsh/.env)"
        "read_file(${home}/.pi/agent/auth.json)"
        "read_file(${home}/.pi/agent/mcp-oauth)"
        "read_file(${home}/.codex/auth.json)"
        "read_file(${home}/.claude/.credentials.json)"
        "read_file(/etc/shadow)"
        "read_file(/etc/gshadow)"
        "read_file(/etc/sudoers)"
        "read_file(/etc/sudoers.d)"
      ]
      ++ lib.optionals isLinux [
        "read_file(/run/secrets)"
        "read_file(/run/secrets.d)"
      ]
      ++ lib.optionals isDarwin [
        "read_file(${home}/Library/Keychains)"
      ];
    };
  };

  cliSettingsBaseFile = pkgs.writeText "antigravity-cli-settings-base.json" (
    builtins.toJSON cliSettingsBase
  );

  settingsPath = "${home}/.gemini/antigravity-cli/settings.json";
  manifestPath = "${home}/.gemini/antigravity-cli/.shell-config-managed-permissions.json";
  mergeCliSettings =
    path: jqOperation:
    lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs path jqOperation;
      format = "json";
      empty = "{}";
      mode = "600";
      staticSettings = cliSettingsBaseFile;
    };

  managedPermissions = ''
    $static.permissions | .deny += (env.SHELL_CONFIG_AGY_RUNTIME_DENIES | fromjson) | .deny |= unique
  '';
in
{
  # Point Antigravity CLI's global skill manifest at the shared ~/.agents/skills
  # directory so it discovers the same skills without duplicating symlinks.
  home.file.".gemini/config/skills.json".text = builtins.toJSON {
    entries = [
      {
        path = "${home}/.agents/skills";
      }
    ];
  };

  # The previous manifest lets activation revoke old managed rules without
  # replacing local permissions or other settings.
  home.activation.antigravityCliSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      if [[ ! -v DRY_RUN ]]; then
        jq=${lib.getExe pkgs.jq}
        manifest=${lib.escapeShellArg manifestPath}
        previous='{}'
        if [[ -s "$manifest" ]]; then
          previous="$("$jq" -cse '
            if length == 1 and (.[0] | type == "object")
            then .[0] else error("expected one permission manifest object") end
          ' "$manifest")"
        fi

        ${
          if isLinux then
            ''
              runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${lib.getExe' pkgs.coreutils "id"} -u)}"
            ''
          else
            ''
              runtime_dir="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR)"
            ''
        }
        runtime_dir="''${runtime_dir%/}"
        mount=${lib.escapeShellArg config.sops.defaultSecretsMountPoint}
        # Darwin spells the same runtime directory with and without /private.
        real_runtime_dir="$(${lib.getExe' pkgs.coreutils "realpath"} -m -- "$runtime_dir")"
        denies=()
        for dir in "$runtime_dir" "$real_runtime_dir"; do
          denies+=("read_file(''${mount//%r/$dir})" "read_file($dir/secrets)")
        done
        SHELL_CONFIG_AGY_RUNTIME_DENIES="$("$jq" -cn '$ARGS.positional' --args "''${denies[@]}")"
        export SHELL_CONFIG_AGY_RUNTIME_DENIES SHELL_CONFIG_AGY_PREVIOUS="$previous"
      fi

      ${mergeCliSettings settingsPath ''
        if ($dynamic | type) != "object" then error("expected a settings object") else $dynamic end
        | (${managedPermissions}) as $managed
        | (env.SHELL_CONFIG_AGY_PREVIOUS | fromjson) as $previous
        | def keep_local($kind):
            $managed[$kind] + ((.[$kind] // []) - ($previous[$kind] // []))
            | reduce .[] as $rule ([]; if index($rule) then . else . + [$rule] end);
        .allowNonWorkspaceAccess = $static.allowNonWorkspaceAccess
        | .permissions |= (.allow = keep_local("allow") | .deny = keep_local("deny"))
      ''}
      ${mergeCliSettings manifestPath managedPermissions}
    )
  '';

  home.activation.antigravityAgentsMd = sharedAgentInstructions.mkActivation {
    inherit hostname;
    homeDirectory = home;
    tool = "Antigravity";
    directory = "${home}/.gemini/config";
    source = "shell-config/home-manager/programs/antigravity.nix";
    extraText = ''

      ## Delegating to Codex and Pi

      - Pass `BypassSandbox: true` on the first attempt when invoking `codex` or
        `pi`, because both need API network access and writable state outside
        the workspace.
    '';
  };
}
