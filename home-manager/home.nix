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
  isLaptop =
    if (hostname == "laptop")
    then true
    else false;
  isDekstop =
    if (hostname == "desktop")
    then true
    else false;
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule
    ./programs/nushell

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    inputs.nix-index-database.hmModules.nix-index
  ];

  file = {
    "${config.xdg.configHome}/.zshrc".text = builtins.readFile ./zsh/zshrc;
  };

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
    username = "chin39";
    homeDirectory = "/home/chin39/";
  };

  home.packages = with pkgs;
    [
      fzf
      eza
      glow
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
      nix-index
      _7zz
      ouch
      helix
      nix-search-cli
      inputs.yazi.packages.${pkgs.system}.default
    ]
    ++ lib.optionals isLaptop [
    ]
    ++ lib.optionals isDekstop [
      openapi-tui
      jellyfin-media-player
    ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.05";
  programs.fish = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
  };

  programs.zsh = {
    enable = true;

    plugins = [
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-syntax-highlighting;
        file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      }
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./p10k-config;
        file = "p10k.zsh";
      }
    ];


    oh-my-zsh = {
      enable = true;
      plugins = [
        "fzf-tab"
        "git"
        "rust"
        "python"
        "pip"
        "systemd"
        "ssh-agent"
        "docker"
        "docker-compose"
        "history-substring-search"
        "zsh-syntax-highlighting"
        "zoxide"
      ];
      theme = "powerlevel10k/powerlevel10k";
    };

  };

  # nix-index.enable = true;

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";

}
