# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, hostname
, noGUI
, ...
}:
let
  inherit (pkgs.stdenv) isDarwin isLinux;
  isDesktop = hostname == "desktop";
  isWork = hostname == "work";
  isWsl = hostname == "wsl";
  username = "chin39";

  proxyUrl =
    if (isWsl || isDesktop) then
    # "http://10.0.0.242:10809"
    # "http://192.168.0.101:10809"
      config.sops.secrets."proxy/clash".path
    else if isWork then
      config.sops.secrets."proxy/work".path
    else "";
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule
    ./programs/nushell
    (import ./programs/zsh { inherit lib pkgs isDesktop noGUI proxyUrl; })
    (import ./programs/git { inherit lib pkgs isDesktop noGUI isWork isWsl proxyUrl; })
    (import ./programs/yazi.nix { inherit config; })
    (import ./programs/zellij { inherit lib pkgs config; })
    (import ./programs/sops.nix { inherit config; })

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    inputs.nix-index-database.hmModules.nix-index

    inputs.sops-nix.homeManagerModules.sops
  ] ++ lib.optionals isWsl [
    (import ./programs/rclone.nix { inherit config lib pkgs; })
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-overlays
      inputs.neovim-nightly-overlay.overlays.default
      # (import ../overlays/rust-overlay.nix)

      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages


      (final: prev: {
        zjstatus = inputs.zjstatus.packages.${prev.system}.default;
      })

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";

  home = {
    # useGlobalPkgs = true;
    sessionVariables = lib.mkMerge [
      {
        _ZO_FZF_OPTS = "--preview 'eza -G -a --color auto --sort=accessed --git --icons -s type {2}'";
      }
      # (lib.mkIf (proxyUrl != "") {
      #   http_proxy = proxyUrl;
      #   https_proxy = proxyUrl;
      # })
    ];
    username = username;
    homeDirectory = "/home/${username}";

    # file = {
    #   "${config.home.homeDirectory}/.zshrc".text = builtins.readFile ./zsh/zshrc;
    # };
    packages = with pkgs;
      [
        fd
        fzf
        glow
        conda
        fastfetch
        onefetch
        genact
        angle-grinder
        zellij
        delta
        duf # better df
        tcpdump # monitor tcp

        btop # system monitor
        glances # same thing
        fq # jq for binary formats - tool, language and decoders for working with binary and text formats

        rclone
        gitoxide
        hexyl
        dua
        (_7zz.override { enableUnfree = true; })
        ouch
        helix
        neovim
        pyright
        cachix
        nix-search-cli
        nurl # Generate Nix fetcher calls from repository URLs
        inputs.yazi.packages.${pkgs.system}.default
        zjstatus
        tailspin #  🌀 A log file highlighter 
        age # A simple, modern and secure encryption tool
        sops
        yt-dlp # website video downloader
        ueberzugpp # terminal image preview
        gh # github shell
        procs # A modern replacement for ps written in Rust
        sampler # Tool for shell commands execution, visualization and alerting
      ]
      ++ lib.optionals noGUI [
        cmake
        ninja
      ]
      ++ lib.optionals isDesktop [
        openapi-tui
        inputs.nixgl.packages.${pkgs.system}.nixGLDefault
        jellyfin-media-player
        aria2
      ]
      ++ lib.optionals (!isDesktop) [
        mold
        rustup
      ]
      ++ lib.optionals isWork [
        mypy #  Optional static typing for Python 
      ]
      ++ lib.optionals isWsl [
        # Clangd from clang-tools must come first.
        (hiPrio clang-tools_18)
        marksman
        aria2
      ];
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;

  programs.fish = {
    enable = true;
  };

  programs.bash = {
    enable = true;
    bashrcExtra = "
    if [[ -f /etc/bash/bashrc ]]; then
      source /etc/bash/bashrc
    fi
    ";
    enableCompletion = true;
  };

  programs.nix-index = {
    enable = true;
  };

  programs = {
    zoxide = {
      enable = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableNushellIntegration = true;
    };

    atuin = {
      enable = true;
      enableFishIntegration = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableNushellIntegration = true;

      flags = [
        "--disable-up-arrow"
      ];

      package = pkgs.atuin;
      settings = {
        # auto_sync = false;
        show_preview = true;
        search_mode = "skim";
        style = "compact";
        # sync_frequency = "1h";
        # sync_address = "https://api.atuin.sh";
        update_check = false;
      };
    };

    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        batgrep
        batwatch
        prettybat
      ];
    };

    direnv = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
      enableNushellIntegration = true;
      nix-direnv = {
        enable = true;
      };
    };

    eza = {
      enable = true;
      extraOptions = [
        "--group-directories-first"
      ];
      git = true;
      icons = true;
    };

    ripgrep = {
      arguments = [
        "--colors=line:style:bold"
        "--max-columns-preview"
        "--smart-case"
      ];
      enable = true;
    };

    neovim = {
      enable = true;
      defaultEditor = true;
      package = pkgs.neovim;
    };

    gitui.enable = true;

    lazygit = {
      enable = true;
      settings = {
        git = {
          paging = {
            colorArg = "always";
            pager = "delta --dark --paging=never";
          };
          commit = {
            signOff = true;
          };
        };
      };
    };
  };


  xdg = {
    enable = isLinux;
    userDirs = {
      enable = isLinux;
      createDirectories = lib.mkDefault true;
      extraConfig = {
        XDG_SCREENSHOTS_DIR = "${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
  };

  systemd.user.services.mbsync.Unit.After = [ "sops-nix.service" ];
  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";
}
