{
  inputs,
  outputs,
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
      stateVersion,
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
      stateVersion,
      username ? "chin39",
      desktop ? null,
      platform ? "x86_64-linux",
      extraModules ? [ ],
      # Names of local binary caches (from lib/caches.nix) this host should use.
      localCaches ? [ ],
    }:
    let
      isWsl = builtins.substring 0 3 hostname == "wsl";
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
          localCacheSubstituters
          localCacheTrustedKeys
          ;
      };
      modules = [
        ../nixos/configuration.nix
        { system.stateVersion = stateVersion; }
      ]
      ++ extraModules
      ++ inputs.nixpkgs.lib.optionals isWsl [ inputs.nixos-wsl.nixosModules.default ];
    };

  mkDarwin =
    {
      desktop ? "aqua",
      hostname,
      username ? "chin39",
      platform ? "aarch64-darwin",
    }:
    inputs.nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit
          inputs
          outputs
          desktop
          hostname
          platform
          username
          ;
      };
      modules = [ ../darwin ];
    };
}
