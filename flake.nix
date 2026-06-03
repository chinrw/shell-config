{
  description = "chin39-config";

  nixConfig = {
    substituters = [
      # local LAN binary cache (vm-nix nix-serve)
      # personal cache server
      "https://chinrw.cachix.org"
      # cache mirror located in China
      # status: https://mirror.sjtu.edu.cn/
      # "https://mirror.sjtu.edu.cn/nix-channels/store"
      # status: https://mirrors.ustc.edu.cn/status/
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
      # Tuna mirror
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store/"
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "chinrw.cachix.org-1:TShvVLuNeWsGoLW2/VGdUT4k8T+03RuQEXA6ZiN16Rw="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # NOTE: nixos-unstable carries extra tests, so nixpkgs-unstable is usually
    # newer — use it where we want the latest packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    # NOTE: checking the repo for the latest stable release
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    hardware.url = "github:NixOS/nixos-hardware";

    # use hermes own flake
    hermes-agent.url = "github:NousResearch/hermes-agent";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    _1password-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    flake-utils.url = "github:numtide/flake-utils";

    neovim-nightly-overlay = {
      url = "github:chinrw/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    rustowl-overlay = {
      url = "github:nix-community/rustowl-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    yazi.url = "github:sxyazi/yazi";
    yazi.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs-unstable";

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    linux-src = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git?ref=linux-rolling-stable&shallow=1";
      flake = false;
    };

    # support for wsl
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Rust development
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cachix-deploy-flake = {
      url = "github:cachix/cachix-deploy-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Zellij plugin
    zjstatus.url = "github:dj95/zjstatus";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs-unstable";
    zjstatus.inputs.rust-overlay.follows = "rust-overlay";

    everything-claude-code = {
      url = "github:affaan-m/everything-claude-code?ref=main";
      flake = false;
    };

    mtg-agent-skill = {
      url = "github:chinrw/mtg-agent-skill?ref=main";
      flake = false;
    };

    claude-code-nix = {
      url = "github:chinrw/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    pwndbg = {
      url = "github:pwndbg/pwndbg";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # nix-darwin: NixOS-style system management for macOS
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      flake-utils,
      rust-overlay,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      systems = [
        "aarch64-linux"
        "x86_64-linux"
        "aarch64-darwin"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
      stateVersion = "25.05";
      helpers = import ./lib { inherit inputs outputs stateVersion; };

    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
      {
        devShells = {
          rust = import ./shell/rust.nix { inherit pkgs inputs; };
          hm = import ./shell/home-manager.nix { inherit pkgs inputs; };
          kernel = import ./shell/kernel.nix { inherit pkgs inputs; };
        };
        # formatter used by `nix fmt`
        formatter = pkgs.nixfmt-tree;
      }
    )
    // {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      deploy.vm-nix = inputs.cachix-deploy-flake.lib.spec {
        agents = {
          vm-nix = self.nixosConfigurations.vm-nix.config.system.build.toplevel;
        };
      };

      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      # nixosModules = import ./modules/nixos;

      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # homeManagerModules = import ./modules/home-manager;

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        "wsl" = helpers.mkNixos {
          hostname = "wsl";
          GPU = "nvidia";
        };
        "wsl-mini" = helpers.mkNixos {
          hostname = "wsl-mini";
          GPU = "amd";
        };
        "vm-nix" = helpers.mkNixos {
          hostname = "vm-nix";
          GPU = "amd";
        };
      };

      # nix-darwin configuration entrypoint
      # Available through 'darwin-rebuild switch --flake .#macos'
      darwinConfigurations = {
        "macos" = helpers.mkDarwin {
          hostname = "macos";
        };
      };
      # Standalone home-manager configuration entrypoint
      # Available through 'home-manager --flake .#your-username@your-hostname'
      homeConfigurations = {
        "chin39@desktop" = helpers.mkHome {
          hostname = "desktop";
          noGUI = false;
        };
        "chin39@wsl-mini" = helpers.mkHome {
          username = "chin39";
          hostname = "wsl-mini";
          noGUI = false;
        };
        "chin39@wsl" = helpers.mkHome {
          username = "chin39";
          hostname = "wsl";
          noGUI = false;
        };
        "ruowen@ringo" = helpers.mkHome {
          username = "ruowen";
          hostname = "gentoo";
          noGUI = false;
          isServer = true;
        };
        "chin39@archlinux" = helpers.mkHome {
          hostname = "archlinux";
          isServer = true;
          isPublic = true;
          smallNode = true;
        };
        "chin39@arch-lxc" = helpers.mkHome {
          hostname = "arch-lxc";
          isServer = true;

        };
        "chin39@proxmox" = helpers.mkHome {
          hostname = "proxmox";
          isServer = true;
          localCaches = [ "home" ];
        };
        "chin39@arch-vm" = helpers.mkHome {
          hostname = "arch";
          isServer = false;
        };
        "chin39@vm-gentoo" = helpers.mkHome {
          hostname = "vm-gentoo";
          platform = "aarch64-linux";
        };
        "chin39@vm-work" = helpers.mkHome {
          hostname = "work";
          platform = "aarch64-linux";
        };
        "chin39@gentoo-server" = helpers.mkHome {
          hostname = "gentoo-server";
          isServer = true;
          localCaches = [ "home" ];
        };
        "chin39@vm-nix" = helpers.mkHome {
          hostname = "vm-nix";
          isServer = true;
          noGUI = true;
          localCaches = [ "home" ];
        };
        "chin39@jd-cloud" = helpers.mkHome {
          hostname = "jd-cloud";
          isServer = true;
          isPublic = true;
          noGUI = true;

          smallNode = true;
        };
        "chin39@macos" = helpers.mkHome {
          hostname = "macos";
          platform = "aarch64-darwin";
        };
        "chin39@work" = helpers.mkHome {
          hostname = "work";
          localCaches = [ "home" ];
        };
      };
    };
}
