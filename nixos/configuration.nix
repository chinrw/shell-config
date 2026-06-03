# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  lib,
  outputs,
  config,
  pkgs,
  isWsl,
  GPU,
  platform,
  hostname,
  username,
  localCacheSubstituters,
  localCacheTrustedKeys,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd
    inputs.sops-nix.nixosModules.sops

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix

    # Import your generated (nixos-generate-config) hardware configuration
    # ./hardware-configuration.nix
  ]
  ++ lib.optionals (hostname == "wsl") [
    ./wsl.nix
    ./services/samba/wsl-server.nix
    ./nvidia-wsl.nix
    ./services/nvidia-container.nix
    ./services/llm.nix
  ]
  ++ lib.optionals (hostname == "wsl-mini") [
    ./wsl-mini.nix
    ./services/github-runners.nix
  ]
  ++ lib.optionals (hostname == "vm-nix") [
    ./vm-nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
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
        # Enable flakes and new 'nix' command
        experimental-features = [ "nix-command flakes" ];

        # Opinionated: disable global registry
        # flake-registry = "";
        #
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;

        trusted-users = [ "chin39" ];
        auto-optimise-store = true;
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
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        features.cdi = true;
      };
    };
    daemon.settings = {
      features.cdi = true;
    };
  };

  environment.systemPackages = with pkgs; [
    # Flakes clones its dependencies through the git command,
    # so git must be installed first
    git
    tzdata
    nodejs
    unzip
    wget
    curl
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
    nix-ld = {
      enable = true;
    };

    zsh.enable = true;
    fuse.userAllowOther = true;
  };

  # zramSwap = {
  #   enable = true;
  # };

  time.timeZone = "Asia/Shanghai";

  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      X11Forwarding = true;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
