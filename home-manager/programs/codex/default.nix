# ~/.codex/AGENTS.md — Codex's user-scope instruction file, the counterpart to
# ~/.claude/CLAUDE.md.
#
# Not managed with home.file: that produces a read-only store symlink, and the
# same path has to absorb host-local additions. Assembled in activation from
# the Nix base plus an untracked AGENTS.local.md, mirroring how CLAUDE.md is
# built in ../claude-code/default.nix.
#
# Codex writes config.toml at runtime, so declared preferences must be merged
# into a writable file rather than linked from the Nix store.
{
  config,
  inputs,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  codexPackage = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codexZshCompletion = pkgs.runCommand "codex-zsh-completion" { } ''
    export HOME="$TMPDIR"
    mkdir -p "$HOME/.local/bin" "$out/share/zsh/site-functions"
    ${codexPackage}/bin/codex completion zsh > "$out/share/zsh/site-functions/_codex"
  '';
  sharedAgentInstructions = import ../agent-instructions { inherit lib pkgs; };
  renameHook = pkgs.writeShellApplication {
    name = "codex-rename-first-turn";
    runtimeInputs = [
      pkgs.git
      (pkgs.python3.withPackages (ps: [ ps.psutil ]))
      codexPackage
    ];
    text = ''
      exec python3 ${./rename-first-turn.py}
    '';
  };
  renameCommand = {
    type = "command";
    # Keep dependency upgrades out of the trust hash, but require review when
    # the naming script changes. Codex hashes the command, not its target.
    command =
      "CODEX_RENAME_SCRIPT_SHA256=${builtins.hashFile "sha256" ./rename-first-turn.py} "
      + lib.escapeShellArg "${config.home.homeDirectory}/.codex/bin/codex-rename-first-turn";
    timeout = 10;
  };
in
{
  home.packages = [
    codexZshCompletion
  ];

  programs.codex = {
    enable = true;
    package = codexPackage;
    mutableSettings = true;
    settings = {
      model_context_window = 1000000;
      model_auto_compact_token_limit = 700000;
      personality = "none";
      approvals_reviewer = "auto_review";
      features.memories = true;
      plugins."superpowers@openai-curated".enabled = false;
      tui = {
        status_line = [
          "model-with-reasoning"
          "current-dir"
          "git-branch"
          "run-state"
          "context-used"
          "five-hour-limit"
          "task-progress"
          "weekly-limit"
        ];
        keymap = {
          global = {
            open_external_editor = "ctrl-x ctrl-e";
            open_transcript = "ctrl-o";
            copy = "alt-c";
            toggle_fast_mode = "alt-o";
          };
        };
      };
    };
  };

  home.file.".codex/bin/codex-rename-first-turn".source = "${renameHook}/bin/codex-rename-first-turn";

  home.file.".codex/hooks.json".text = builtins.toJSON {
    hooks = {
      SessionStart = [
        {
          matcher = "^startup$";
          hooks = [ renameCommand ];
        }
      ];
      UserPromptSubmit = [ { hooks = [ renameCommand ]; } ];
      Stop = [
        {
          hooks = [
            (
              renameCommand
              // {
                async = true;
                timeout = 90;
              }
            )
          ];
        }
      ];
    };
  };

  # The activation below rewrites AGENTS.md on every switch. Say so in the file
  # itself: ~/.codex/AGENTS.md is the path Codex documents, so it is the one a
  # person or an agent will hand-edit unless told otherwise.
  home.activation.codexAgentsMd = sharedAgentInstructions.mkActivation {
    inherit hostname;
    homeDirectory = config.home.homeDirectory;
    tool = "Codex";
    directory = "${config.home.homeDirectory}/.codex";
    source = "shell-config/home-manager/programs/codex/";
  };
}
