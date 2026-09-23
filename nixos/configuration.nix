# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  lib,
  outputs,
  config,
  pkgs,
  username,
  localCacheSubstituters,
  localCacheTrustedKeys,
  ...
}:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
      outputs.overlays.llvm-pin
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.stable-packages
      outputs.overlays.unstable-packages

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
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = [ "nix-command" "flakes" ];
        auto-optimise-store = true;
        # Opinionated: disable global registry
        # flake-registry = "";
        #
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;

        trusted-users = [ "chin39" ];
        keep-outputs = true;
        keep-derivations = true;
        # access-tokens = "@config.sops.secrets.path";
      }
      # Local binary caches selected per-host via `localCaches` in flake.nix and
      # resolved from lib/caches.nix. No-op unless a host opts in. This writes the
      # daemon's own /etc/nix/nix.conf, so it is honored without the trusted-user
      # dance the home-manager path needs.
      // lib.optionalAttrs (localCacheSubstituters != [ ]) {
        extra-substituters = localCacheSubstituters;
        extra-trusted-public-keys = localCacheTrustedKeys;
      };
      # Opinionated: disable channels
      channel.enable = false;

      # auto cleanup
      gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault "03:15";
        options = lib.mkDefault "--delete-older-than 21d";
        randomizedDelaySec = lib.mkDefault "45min";
      };

      # Opinionated: make flake registry and nix path match flake inputs.
      # `nixpkgs` is dropped from the map on purpose: nixpkgs' own
      # misc/nixpkgs-flake.nix pins the `nixpkgs` registry key to whichever
      # nixpkgs built this system, so we let it be the sole owner of that key
      # (same approach as darwin/configuration.nix). This avoids a conflicting
      # `nix.registry.nixpkgs` definition and stays correct regardless of how the
      # system's nixpkgs input is named or which channel a host builds from.
      # nixPath still maps `nixpkgs` (a registry indirection) so `<nixpkgs>` stays
      # defined — our normal-priority list would otherwise suppress the module's
      # mkDefault nixPath entry.
      registry =
        lib.mapAttrs (_: flake: { inherit flake; }) (removeAttrs flakeInputs [ "nixpkgs" ]);
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  virtualisation.docker = {
    enable = lib.mkDefault true;
    rootless = {
      enable = lib.mkDefault true;
      setSocketVariable = lib.mkDefault true;
      daemon.settings = {
        features.cdi = true;
      };
    };
    daemon.settings = {
      features.cdi = true;
    };
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    tzdata
    nodejs
    unzip
    wget
    inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.default
    (lib.hiPrio clang)
    (lib.hiPrio llvm)
    gcc
    rustc
    cargo
    mold
    wireguard-tools
    ueberzugpp
    tcpdump
    trash-cli
    gnumake
    pnpm_12

    btrfs-progs
    bpftools
    bpftrace
    lsof
    psmisc
    perf
    osc # Access the system clipboard from anywhere using the ANSI OSC52 sequence
  ];
  # Set the default editor to vim
  environment.variables = {
    EDITOR = "nvim";
  };

  programs = {
    zsh.enable = true;
    nix-ld = {
      enable = true;
    };

    fuse = {
      enable = lib.mkDefault true;
      userAllowOther = lib.mkDefault true;
    };
  };

  systemd.tmpfiles.rules = [
    # M: age dirs by mtime only. / is relatime, so any /tmp traversal resets
    # dir atime and a plain age rule never fires. 21d spans a multi-day PR
    # cycle of agent scratch.
    "d /tmp 1777 root root acmM:21d"
    # cargo only flock()s this file, so its timestamps never move and the
    # cleaner would take it; the next cargo then locks a fresh inode and two
    # builds share one target dir.
    "x /tmp/*/*/.cargo-lock"
    "x /tmp/*/*/*/.cargo-lock"
  ];

  # zramSwap = {
  #   enable = true;
  # };

  time.timeZone = lib.mkDefault "Asia/Shanghai";

  users.users.${username} = {
    isNormalUser = lib.mkDefault true;
  };

  services.openssh = {
    enable = lib.mkDefault true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      X11Forwarding = lib.mkDefault true;
    };
  };

  # A fuse filesystem that dynamically populates contents of /bin and /usr/bin/
  # so that it contains all executables from the PATH of the requesting
  # process. This allows executing FHS based programs on a non-FHS system. For
  # example, this is useful to execute shebangs on NixOS that assume hard coded
  # locations like /bin or /usr/bin etc.
  services.envfs.enable = lib.mkDefault true;

}
