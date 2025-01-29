{ inputs
, outputs
, stateVersion
, ...
}:
{
  # Helper function for generating home-manager configs
  mkHome =
    { hostname
    , username ? "chin39"
    , noGUI ? true
    , platform ? "x86_64-linux"
    , isServer ? false
    ,
    }:
    let
      isWsl = builtins.substring 0 3 hostname == "wsl";
      isWork = builtins.substring 0 4 hostname == "work";
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.${platform};
      extraSpecialArgs = {
        inherit
          inputs
          outputs
          noGUI
          hostname
          platform
          username
          stateVersion
          isWsl
          isWork
          isServer
          ;
      };
      modules = [ ../home-manager/home.nix ];
    };

  # Helper function for generating NixOS configs
  mkNixos =
    { hostname
    , username ? "chin39"
    , desktop ? null
    , platform ? "x86_64-linux"
    ,
    }:
    let
      isISO = builtins.substring 0 4 hostname == "iso-";
      isInstall = !isISO;
      isLima = builtins.substring 0 5 hostname == "lima-";
      isWorkstation = builtins.isString desktop;
    in
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit
          inputs
          outputs
          desktop
          hostname
          platform
          username
          stateVersion
          isInstall
          isLima
          isISO
          isWorkstation
          ;
      };
      # If the hostname starts with "iso-", generate an ISO image
      modules =
        let
          cd-dvd =
            if (desktop == null) then
              inputs.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            else
              inputs.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-graphical-calamares.nix";
        in
        [ ../nixos ] ++ inputs.nixpkgs.lib.optionals isISO [ cd-dvd ];
    };

  mkDarwin =
    { desktop ? "aqua"
    , hostname
    , username ? "chin39"
    , platform ? "aarch64-darwin"
    ,
    }:
    let
      isISO = false;
      isInstall = true;
      isLima = false;
      isWorkstation = true;
    in
    inputs.nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit
          inputs
          outputs
          desktop
          hostname
          platform
          username
          stateVersion
          isInstall
          isLima
          isISO
          isWorkstation
          ;
      };
      modules = [ ../darwin ];
    };

  forAllSystems = inputs.nixpkgs.lib.genAttrs [
    "aarch64-linux"
    "x86_64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
  ];
}
