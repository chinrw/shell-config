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

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    inputs.nix-index-database.hmModules.nix-index
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-overlays
      # inputs.neovim-nightly-overlay.overlays

      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    # config = {
    #   # Disable if you don't want unfree packages
    #   allowUnfree = true;
    #   # Workaround for https://github.com/nix-community/home-manager/issues/2942
    # };
  };

  home = {
    # useGlobalPkgs = true;
    sessionVariables = {
      http_proxy = "http://10.0.0.242:10809";
      https_proxy = "http://10.0.0.242:10809";
      _ZO_FZF_OPTS = "--preview 'eza -G -a --color auto --sort=accessed --git --icons -s type {2}'";
    };
    username = username;
    homeDirectory = "/home/${username}";

    # file = {
    #   "${config.home.homeDirectory}/.zshrc".text = builtins.readFile ./zsh/zshrc;
    # };
    packages = with pkgs;
      [
        fzf
        eza
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
        _7zz
        ouch
        helix
        nix-search-cli
        inputs.yazi.packages.${pkgs.system}.default
      ]
      ++ lib.optionals isLaptop [
      ]
      ++ lib.optionals isDesktop [
        openapi-tui
        jellyfin-media-player
      ];

  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  programs.fish = {
    enable = true;
  };

  programs.atuin = {
    enable = true;
    enableNushellIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;

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

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };

  programs.nix-index = {
    enable = true;
  };

  home.stateVersion = "24.05";

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
