# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, lib
, config
, pkgs
, hostname
, ...
}:
let
  neovim-overlays = [
    inputs.neovim-nightly-overlay.overlay
  ];
  isLaptop = if (hostname == "laptop") then true else false;
  isDekstop = if (hostname == "desktop") then true else false;
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule
    ./programs/nushell

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-overlays
      inputs.neovim-nightly-overlay.overlay

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


  # Add stuff for your user as you see fit:
  # programs.neovim.enable = true;
  home.packages = with pkgs; [
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
  ] ++ lib.optionals (isLaptop) [
  ] ++ lib.optionals (isDekstop) [
    openapi-tui
    jellyfin-media-player
  ];

  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # Nicely reload system units when changing configs
  # systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.05";
  programs.fish = {
    enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableNushellIntegration = true;
  };


  # programs.zsh = {
  #   enable = true;
  # };

}
