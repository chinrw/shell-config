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
      pkgs = inputs.nixpkgs-hm.legacyPackages.${platform};
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
    , GPU ? null
    , platform ? "x86_64-linux"
    ,
    }:
    let
      isWsl = builtins.substring 0 3 hostname == "wsl";
      # isISO = builtins.substring 0 4 hostname == "iso-";
      # isInstall = !isISO;
      # isLima = builtins.substring 0 5 hostname == "lima-";
      isWorkstation = builtins.isString desktop;
    in
    inputs.nixpkgs.lib.nixosSystem {
      system = platform;
      specialArgs = {
        inherit
          inputs
          outputs
          desktop
          hostname
          platform
          username
          stateVersion
          isWsl
          GPU
          isWorkstation
          ;
      };
      modules =
        [ ../nixos/configuration.nix ] ++ inputs.nixpkgs.lib.optionals isWsl [ inputs.nixos-wsl.nixosModules.default ];
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
    "x86_64-linux"
    "aarch64-darwin"
  ];
}
