{
  description = "chin39-config";

  nixConfig = {
    substituters = [
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
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:nixos/nixpkgs";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    _1password-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    neovim-nightly-overlay = {
      url = "github:chinrw/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    yazi.url = "github:sxyazi/yazi";
    yazi.inputs.nixpkgs.follows = "nixpkgs";

    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # support for wsl
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    # Rust development
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Zellij plugin
    zjstatus.url = "github:dj95/zjstatus";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , flake-utils
    , rust-overlay
    , ...
    } @ inputs:
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
    flake-utils.lib.eachDefaultSystem
      (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
      {
        devShells.rust = import ./shell/rust.nix { inherit pkgs inputs; };
        devShells.hm = import ./shell/home-manager.nix { inherit pkgs inputs; };
      })
    // {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

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
      };

      nixosConfigurations = {
        "wsl-mini" = helpers.mkNixos {
          hostname = "wsl-mini";
          GPU = "amd";
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
        };
        "chin39@arch-vm" = helpers.mkHome {
          hostname = "arch";
          isServer = false;
        };
        "chin39@vm-gentoo" = helpers.mkHome {
          hostname = "vm-gentoo";
          platform = "aarch64-linux";
        };
        "chin39@wsl-gentoo" = helpers.mkHome {
          hostname = "gentoo-vm";
        };
        "chin39@macos" = helpers.mkHome {
          hostname = "macos";
          platform = "aarch64-darwin";
        };
        "chin39@work" = helpers.mkHome {
          hostname = "work";
        };
      };
    };
}
