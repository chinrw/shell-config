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
  isLaptop = hostname == "laptop" || hostname == "work";
  isDesktop = hostname == "desktop";
  isWork = hostname == "work";
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
        genact
        angle-grinder
        zellij
        delta

        rclone
        gitoxide
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
  programs.git = {
    enable = true;
    aliases =
      {
        co = "checkout";
      };
    delta.enable = false;
    delta.options = {
      decorations = {
        commit-decoration-style = "bold yellow box ul";
        file-style = "bold yellow ul";
        file-decoration-style = "none";
        hunk-header-decoration-style = "yellow box";
      };

      unobtrusive-line-numbers = {
        line-numbers = true;
        line-numbers-minus-style = "#444444";
        line-numbers-zero-style = "#444444";
        line-numbers-plus-style = "#444444";
        line-numbers-left-format = "{nm:>4}┊";
        line-numbers-right-format = "{np:>4}│";
        line-numbers-left-style = "blue";
        line-numbers-right-style = "blue";
      };

      navigate = true; # use n and N to move between diff sections
      light = false; # set to true if you're in a terminal
      side-by-side = true;
      features = "unobtrusive-line-numbers decorations mantis-shrimp";
      whitespace-error-style = "22 reverse";
      true-color = "always";
    };
    difftastic.enable = true;


    userName = "Ruowen Qin";
    userEmail = if (!isWork) then "chinqrw@gmail.com" else "ruqin@redhat.com";

    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMasqR2edNuMaTk0djcs46/s/OiIQo97qa6oyF/ybgih";
      signByDefault = true;
    };
    extraConfig = {
      core = {
        packedGitLimit = "512m";
        packedGitWindowSize = "512m";
      };
      pack = {
        deltaCacheSize = "2047m";
        packSizeLimit = "2047m";
        windowMemory = "2047m";
      };

      gpg.format = "ssh";
      pull.rebase = true;
      merge.conflictstyle = "zdiff3";
      init.defaultBranch = "main";
      interactive.diffFilter = "delta --color-only";
    };
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

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";
}
