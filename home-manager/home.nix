# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, hostname
, ...
}:
let
  inherit (pkgs.stdenv) isDarwin isLinux;
  isLaptop =
    if (hostname == "laptop")
    then true
    else false;
  isDesktop =
    if (hostname == "desktop")
    then true
    else false;
  username = "chin39";
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule
    ./programs/nushell
    (import ./programs/zsh { inherit lib pkgs isDesktop isLaptop; })
    # (import ./programs/zellij { inherit lib pkgs isDarwin isDesktop isLaptop; })

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    inputs.nix-index-database.hmModules.nix-index
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
      (lib.mkIf isDesktop {
        http_proxy = "http://10.0.0.242:10809";
        https_proxy = "http://10.0.0.242:10809";
      })
    ];
    username = username;
    homeDirectory = "/home/${username}";

    file."${config.xdg.configHome}/zellij" = {
      source = ../zellij;
      recursive = true;
    };

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
        gitui
        genact
        angle-grinder
        zellij
        rclone
        gitoxide
        lazygit
        hexyl
        dua
        (_7zz.override { enableUnfree = true; })
        ouch
        helix
        neovim
        cachix
        nix-search-cli
        nurl # Generate Nix fetcher calls from repository URLs
        inputs.yazi.packages.${pkgs.system}.default
        zjstatus
        tailspin #  🌀 A log file highlighter 
      ]
      ++ lib.optionals isLaptop [
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
      ];
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  programs.fish = {
    enable = true;
  };

  programs.bash = {
    enable = true;
    bashrcExtra = "
      source /etc/bash/bashrc
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

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";
}
