# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, username
, stateVersion
, isWsl
, isWork
, hostname
, noGUI
, isServer
, platform
, ...
}:
let
  inherit (pkgs.stdenv) isDarwin isLinux;
  isDesktop = hostname == "desktop";

  proxyUrl =
    if (hostname == "wsl"|| isDesktop) then
    # "http://10.0.0.242:10809"
    # "http://192.168.0.101:10809"
      config.sops.secrets."proxy/clash".path
    else if isWork then
      ""
    else if (hostname == "wsl-mini") then
      config.sops.secrets."proxy/clash_mini".path
    else "";
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule
    ./programs/nushell
    (import ./programs/zsh { inherit lib pkgs isDesktop noGUI proxyUrl; })
    (import ./programs/git { inherit lib pkgs isDesktop noGUI isWork hostname proxyUrl; })
    (import ./programs/zellij { inherit lib pkgs config; })
    (import ./programs/sops.nix { inherit config isServer; })

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    inputs.nix-index-database.hmModules.nix-index
    inputs._1password-shell-plugins.hmModules.default
    inputs.sops-nix.homeManagerModules.sops
  ] ++ lib.optionals (hostname == "wsl") [
    (import ./programs/rclone.nix { inherit config lib pkgs; })
  ] ++ lib.optionals (hostname != "wsl") [
    (import ./programs/yazi.nix { inherit config; })
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # (import ../overlays/rust-overlay.nix)


      (final: prev: {
        zjstatus = inputs.zjstatus.packages.${prev.system}.default;
      })

      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
      # ] ++ lib.optionals (builtins.isString platform && !builtins.match "aarch64" platform) [
    ] ++ lib.optionals (!(builtins.match "aarch64.*" platform != null)) [


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

  home = {
    inherit stateVersion;
    inherit username;

    # useGlobalPkgs = true;
    # stateVersion = ${stateVersion};
    sessionVariables = lib.mkMerge [
      {
        _ZO_FZF_OPTS = "--preview 'eza -G -a --color auto --sort=accessed --git --icons -s type {2}'";
      }
      # (lib.mkIf (proxyUrl != "") {
      #   http_proxy = proxyUrl;
      #   https_proxy = proxyUrl;
      # })
    ];
    homeDirectory = if (hostname == "macos") then "/Users/${username}" else "/home/${username}";

    # file = {
    #   "${config.home.homeDirectory}/.zshrc".text = builtins.readFile ./zsh/zshrc;
    # };
    packages = with pkgs;
      [
        fd
        fzf
        glow
        go
        fastfetch
        onefetch
        genact
        angle-grinder
        zellij
        man-pages
        duf # better df
        tcpdump # monitor tcp
        b4 # A tool to work with public-inbox and patch archives
        moreutils # check errno
        dstask # Git powered terminal-based todo/note manager -- markdown note page per task

        # (pkgs.dstask.overrideAttrs ({ meta ? { }, ... }: {
        #   meta = meta // {
        #     platforms = pkgs.lib.platforms.unix;
        #   };
        # }))

        btop # system monitor
        glances # same thing
        fq # jq for binary formats - tool, language and decoders for working with binary and text formats

        rclone
        gitoxide
        git-lfs
        hexyl
        dua
        (_7zz.override { enableUnfree = true; })
        ouch
        helix
        pyright
        cachix
        nix-search-cli
        nurl # Generate Nix fetcher calls from repository URLs
        inputs.yazi.packages.${pkgs.system}.default
        mediainfo
        ffmpegthumbnailer # yazi deps
        exiftool
        zjstatus
        tailspin #  🌀 A log file highlighter 
        age # A simple, modern and secure encryption tool
        sops
        yt-dlp # website video downloader
        ueberzugpp # terminal image preview
        gh # github shell
        procs # A modern replacement for ps written in Rust
        sampler # Tool for shell commands execution, visualization and alerting
        nmap # port scanner
        circumflex # 🌿 It's Hacker News in your terminal
        aria2 # downloader
        delta # A syntax-highlighting pager for git, diff, grep, and blame output
        tokei # Count your code, quickly.
        binsider # Analyze ELF binaries like a boss 😼🕵️‍♂️
        hyperfine # A command-line benchmarking tool
        htop
        devenv # Fast, Declarative, Reproducible, and Composable Developer Environments
      ]
      ++ lib.optionals (hostname != "macos") [
        conda
      ]
      ++ lib.optionals (!noGUI) [
        mpv
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
      ++ lib.optionals (!isWork) [
      ]
      ++ lib.optionals isWsl [
        # Clangd from clang-tools must come first.
        (hiPrio clang-tools)
        par2cmdline
        vim
        marksman
        aria2
        gdb
        gef # GEF (GDB Enhanced Features) - a modern experience for GDB with advanced debugging capabilities for exploit devs & reverse engineers on Linux
      ];
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;

  programs._1password-shell-plugins = {
    # enable 1Password shell plugins for bash, zsh, and fish shell
    enable = true;
    # the specified packages as well as 1Password CLI will be
    # automatically installed and configured to use shell plugins
    plugins = with pkgs; [ awscli2 ];
  };


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
      enableNushellIntegration = true;
      enableBashIntegration = false;

      flags = [
        "--disable-up-arrow"
      ];

      package = pkgs.atuin;
      settings = {
        show_preview = true;
        search_mode = "fuzzy";
        secrets_filter = true;
        style = "compact";
        auto_sync = true;
        sync_frequency = "1h";
        sync_address = "http://10.0.0.242:8881";
        key_path = config.sops.secrets.atuin_key.path;
        update_check = false;
        filter_mode = "host";
      };
    };

    bat = {
      enable = true;
      extraPackages = with pkgs.bat-extras; [
        # batgrep
        # batwatch
        # prettybat
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
      config = {
        hide_env_diff = true;
      };
    };

    eza = {
      enable = true;
      extraOptions = [
        "--group-directories-first"
      ];
      git = true;
      icons = "auto";
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
      package = inputs.neovim-nightly-overlay.packages.${pkgs.system}.default;
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
