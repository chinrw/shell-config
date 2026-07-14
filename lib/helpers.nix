{
  inputs,
  outputs,
  stateVersion,
  ...
}:
let
  # Local binary cache registry (name -> { url; publicKey; }); see lib/caches.nix.
  caches = import ./caches.nix;
  # Resolve cache names to { substituters; trustedKeys; }, failing loudly on a
  # typo or unknown name. Shared by mkHome and mkNixos.
  resolveCaches =
    hostname: names:
    let
      known = builtins.attrNames caches;
      lookup =
        name:
        caches.${name} or (throw
          "unknown localCache '${name}' for host '${hostname}'; known caches: ${toString known}"
        );
      resolved = map lookup names;
    in
    {
      substituters = map (c: c.url) resolved;
      trustedKeys = map (c: c.publicKey) resolved;
    };
in
{
  # Helper function for generating home-manager configs
  mkHome =
    {
      hostname,
      username ? "chin39",
      noGUI ? true,
      platform ? "x86_64-linux",
      isServer ? false,
      isPublic ? false,
      smallNode ? false,
      # Names of local binary caches (from lib/caches.nix) this host should use.
      localCaches ? [ ],
    }:
    let
      isWsl = builtins.substring 0 3 hostname == "wsl";
      isWork = builtins.substring 0 4 hostname == "work";
      cacheCfg = resolveCaches hostname localCaches;
      localCacheSubstituters = cacheCfg.substituters;
      localCacheTrustedKeys = cacheCfg.trustedKeys;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs-unstable.legacyPackages.${platform};
      extraSpecialArgs = {
        inherit
          inputs
          outputs
          noGUI
          hostname
          platform
          username
          stateVersion
          smallNode
          isWsl
          isWork
          isServer
          isPublic
          localCacheSubstituters
          localCacheTrustedKeys
          ;
      };
      modules = [ ../home-manager/home.nix ];
    };

  # Helper function for generating NixOS configs
  mkNixos =
    {
      hostname,
      username ? "chin39",
      desktop ? null,
      GPU ? null,
      platform ? "x86_64-linux",
      # Names of local binary caches (from lib/caches.nix) this host should use.
      localCaches ? [ ],
    }:
    let
      isWsl = builtins.substring 0 3 hostname == "wsl";
      # isISO = builtins.substring 0 4 hostname == "iso-";
      # isInstall = !isISO;
      # isLima = builtins.substring 0 5 hostname == "lima-";
      isWorkstation = builtins.isString desktop;
      cacheCfg = resolveCaches hostname localCaches;
      localCacheSubstituters = cacheCfg.substituters;
      localCacheTrustedKeys = cacheCfg.trustedKeys;
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
          localCacheSubstituters
          localCacheTrustedKeys
          ;
      };
      modules = [
        ../nixos/configuration.nix
      ]
      ++ inputs.nixpkgs.lib.optionals isWsl [ inputs.nixos-wsl.nixosModules.default ];
    };

  mkDarwin =
    {
      desktop ? "aqua",
      hostname,
      username ? "chin39",
      platform ? "aarch64-darwin",
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
}
