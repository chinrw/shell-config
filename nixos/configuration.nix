# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{ inputs
, lib
, config
, pkgs
, ...
}: {
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    ./networks
    ./services/samba
    ./services/systemd

    # Import your generated (nixos-generate-config) hardware configuration
    # ./hardware-configuration.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # If you want to use overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

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
      };
      # Opinionated: disable channels
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };





  wsl = {
    enable = true;
    defaultUser = "chin39";
  };

  # enable docker
  virtualisation.docker.enable = true;
  users.users.chin39 = {
    extraGroups = [ "docker" "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMasqR2edNuMaTk0djcs46/s/OiIQo97qa6oyF/ybgih chin39@fedora"
    ];
  };


  environment.systemPackages = with pkgs; [
    # Flakes clones its dependencies through the git command,
    # so git must be installed first
    git
    nodejs
    neovim
    unzip
    wget
    curl
    (hiPrio clang_18)
    (hiPrio llvm_18)
    gcc
    rustc
    cargo
    python3
    mold
    wireguard-tools
    ueberzugpp
    tcpdump

    btrfs-progs
    bpftool
  ];
  # Set the default editor to vim
  environment.variables.EDITOR = "nvim";

  programs = {
    nix-ld = {
      enable = true;
      package = pkgs.nix-ld-rs;
    };

    zsh.enable = true;
    fuse.userAllowOther = true;

    proxychains = {
      enable = true;
      quietMode = true;
      proxies = {
        local = {
          enable = true;
          type = "socks5";
          host = "127.0.0.1";
          port = 7891;
        };
      };
    };
  };



  fileSystems."/mnt/autofs/data" = {
    device = "10.0.0.254:/volume1/Data";
    fsType = "nfs4";
    options = [ "noauto" "x-systemd.automount" "x-systemd.idle-timeout=1h" ];
  };
  time.timeZone = "Asia/Shanghai";

  services.openssh = {
    enable = true;
    ports = [ 22 23 ];
    settings = {
      PasswordAuthentication = true;
      # I'll disable this once I can connect.
      X11Forwarding = true;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.05";
}
