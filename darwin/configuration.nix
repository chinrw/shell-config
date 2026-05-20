{
  inputs,
  lib,
  outputs,
  pkgs,
  username,
  ...
}:
{
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@admin"
          username
        ];
        # Darwin doesn't support auto-optimise-store reliably; use a periodic
        # GC + the store optimiser job instead.
        keep-outputs = true;
        keep-derivations = true;
      };

      # Make `nix run nixpkgs#…` resolve to the same nixpkgs the system was
      # built from. Mirrors the NixOS configuration.
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;

      gc = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        };
        options = "--delete-older-than 30d";
      };

      optimise = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 4;
          Minute = 0;
        };
      };
    };

  # Match the Determinate Systems installer's nixbld GID (30000) instead of
  # nix-darwin's default (350). Without this, activation aborts with
  # "Build user group has mismatching GID". Changing the actual macOS group
  # would require uninstalling & reinstalling Nix, so we align nix-darwin
  # to reality instead.
  ids.gids.nixbld = 30000;

  # Primary user — required by some homebrew + sudo modules.
  system.primaryUser = username;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.iosevka
    nerd-fonts.meslo-lg
    lato
  ];

  # nix-darwin uses an integer schema version (currently 6), unlike NixOS
  # which uses the year.month flake stateVersion.
  system.stateVersion = 6;
}
