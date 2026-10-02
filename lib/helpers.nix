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

  # Opt-in home-manager features, named in a host's `features` list.
  knownFeatures = {
    atuin-sync = "sync shell history with the LAN atuin server";
    chatgpt-linker-tunnel = "run the ChatGPT Linker tunnel with node-local credentials";
    dev-tools = "iperf3, clang-tools, par2cmdline and asciinema";
    nix-gc = "daily nix GC from home-manager (needs localCaches, which owns nix.conf)";
    rclone = "rclone mounts";
    rclone-progress = "rclone progress logging instead of --log-systemd";
    restic = "restic backups";
    syncthing = "syncthing with the shared device list";
  };
  # Check the whole list up front: `builtins.elem` stops at the first match,
  # so a typo after it would otherwise never be reported.
  checkFeatures =
    hostname: features:
    let
      unknown = builtins.filter (f: !(knownFeatures ? ${f})) features;
    in
    if unknown == [ ] then
      features
    else
      throw "unknown feature '${toString unknown}' for host '${hostname}'; known features: ${toString (builtins.attrNames knownFeatures)}";
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
      # Names from knownFeatures above.
      features ? [ ],
      # Where the shell proxy URL comes from: { secret = "<sops key>"; } or
      # { url = "..."; }. Empty means no proxy.
      proxy ? { },
      # http.proxy for git, when git needs a different route than the shell.
      gitProxy ? null,
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
          proxy
          gitProxy
          ;
        features = checkFeatures hostname features;
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
