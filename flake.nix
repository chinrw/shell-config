{
  description = "chin39-config";

  # IMPORTANT: use the appending `extra-*` keys, NOT the replacing
  # `substituters` / `trusted-public-keys` keys. A flake's nixConfig is applied
  # on every `--flake` build (e.g. `home-manager switch --flake`), and the
  # replacing form overwrites each host's nix.conf — which would discard the
  # per-host LAN cache + signing key that `localCaches` (lib/caches.nix) writes
  # via home-manager's `extra-substituters`.
  nixConfig = {
    extra-substituters = [
      # NOTE: per-host LAN caches (e.g. nixos-ci nix-serve) are NOT listed here —
      # per host via `localCaches` in flake.nix -> lib/caches.nix
      "https://chinrw.cachix.org"
      # cache mirror located in China
      # status: https://mirror.sjtu.edu.cn/
      "https://mirror.sjtu.edu.cn/nix-channels/store?priority=39"
      # status: https://mirrors.ustc.edu.cn/status/
      # "https://mirrors.ustc.edu.cn/nix-channels/store"
      # Tuna mirror — ?priority=39 ranks it above cache.nixos.org (40);
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store/?priority=39"
      "https://cache.nixos.org"
    ];
    extra-trusted-public-keys = [
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
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    # The modules are plain paths and never read this nixpkgs. Only the
    # upstream checks do, so following ours just skips a channel tarball.
    hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk layout for work-laptop (nixos/t14p-gen2/disko.nix).
    # `latest` is a moving tag that tracks disko releases.
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # use hermes own flake
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Lossless Context Management engine for hermes, copied into
    # /var/lib/hermes/.hermes/plugins by services/hermes-lcm.nix (the
    # container boot chown breaks on store symlinks). Pin release tags only
    # — the v0.21 line is still rc; back up lcm.db before bumps.
    hermes-lcm = {
      url = "github:stephenschoettler/hermes-lcm/v0.20.0";
      flake = false;
    };

    # Home manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    _1password-shell-plugins = {
      url = "github:1Password/shell-plugins";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    neovim-nightly-overlay = {
      url = "github:chinrw/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    rustowl-overlay = {
      url = "github:nix-community/rustowl-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    yazi.url = "github:sxyazi/yazi";
    yazi.inputs.nixpkgs.follows = "nixpkgs-unstable";

    # `?ref=main` on purpose: the vm-nix updater bumps these with yazi itself.
    yazi-plugin-git = {
      url = "github:yazi-rs/plugins?ref=main";
      flake = false;
    };
    yazi-plugin-augment-command = {
      url = "github:hankertrix/augment-command.yazi?ref=main";
      flake = false;
    };
    yazi-plugin-time-travel = {
      url = "github:iynaix/time-travel.yazi?ref=main";
      flake = false;
    };

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    linux-src = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git?ref=linux-rolling-stable&shallow=1";
      flake = false;
    };

    # China-domain list for AdGuard split DNS on vm-nix: domestic names resolve
    # via AliDNS directly so DNS keeps working when the proxy tunnel is down.
    dnsmasq-china-list = {
      url = "github:felixonmars/dnsmasq-china-list";
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

    # Zellij plugin
    zjstatus.url = "github:dj95/zjstatus";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs-unstable";
    zjstatus.inputs.rust-overlay.follows = "rust-overlay";

    zj-sysinfo.url = "github:chinrw/zj-sysinfo";
    zj-sysinfo.inputs.nixpkgs.follows = "nixpkgs-unstable";
    zj-sysinfo.inputs.rust-overlay.follows = "rust-overlay";

    everything-claude-code = {
      url = "github:affaan-m/everything-claude-code?ref=main";
      flake = false;
    };

    oh-my-opencode-slim = {
      url = "github:alvinunreal/oh-my-opencode-slim?ref=master";
      flake = false;
    };

    opencode-goal-plugin = {
      url = "github:prevalentWare/opencode-goal-plugin?ref=main";
      flake = false;
    };

    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    mtg-agent-skill = {
      url = "github:chinrw/mtg-agent-skill?ref=main";
      flake = false;
    };

    khazix-skills = {
      url = "github:KKKKhazix/khazix-skills?ref=main";
      flake = false;
    };

    agent-skills = {
      url = "github:chinrw/agent-skills?ref=main";
      flake = false;
    };

    chatgpt-linker = {
      url = "github:chinrw/chatgpt-linker";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills?ref=main";
      flake = false;
    };

    claude-code-nix = {
      url = "github:chinrw/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    codex-cli-nix = {
      url = "github:chinrw/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    deepseek-harness-nix = {
      url = "github:chinrw/deepseek-harness-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # nixpkgs deliberately not followed: the fork's CI builds against pi.nix's
    # own pin to use the cache
    pi = {
      url = "github:chinrw/pi.nix";
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
    { self
    , nixpkgs
    , home-manager
    , rust-overlay
    , ...
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
      helpers = import ./lib { inherit inputs outputs; };

      # The dev shells need rust-bin and llvmPinned, which plain
      # legacyPackages does not carry.
      devPkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            (import rust-overlay)
            self.overlays.llvm-pin
          ];
        }
      );
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = devPkgsFor.${system};
        in
        {
          rust = import ./shell/rust.nix { inherit pkgs inputs; };
          hm = import ./shell/home-manager.nix { inherit pkgs inputs; };
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          kernel = import ./shell/kernel.nix { inherit pkgs inputs; };
        }
      );

      # formatter used by `nix fmt`
      formatter = forAllSystems (system: devPkgsFor.${system}.nixfmt-tree);

      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
        import ./pkgs {
          inherit inputs;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        "nixos-ci" = helpers.mkNixos {
          hostname = "nixos-ci";
          stateVersion = "26.11";
          extraModules = [ ./nixos/nixos-ci ];
        };
        "nixos-lxc" = helpers.mkNixos {
          hostname = "nixos-lxc";
          stateVersion = "26.11";
          localCaches = [ "home" ];
          extraModules = [ ./nixos/nixos-lxc ];
        };
        "wsl" = helpers.mkNixos {
          stateVersion = "25.05";
          hostname = "wsl";
          extraModules = [
            ./nixos/wsl.nix
            ./nixos/services/samba/wsl-server.nix
            ./nixos/nvidia-wsl.nix
            ./nixos/services/nvidia-container.nix
            ./nixos/services/llm.nix
          ];
        };
        "wsl-mini" = helpers.mkNixos {
          stateVersion = "25.05";
          hostname = "wsl-mini";
          extraModules = [ ./nixos/wsl-mini.nix ];
        };
        "vm-nix" = helpers.mkNixos {
          stateVersion = "25.05";
          hostname = "vm-nix";
          localCaches = [ "home" ];
          extraModules = [ ./nixos/vm-nix ];
        };
        "work-laptop" = helpers.mkNixos {
          stateVersion = "25.05";
          hostname = "work-laptop";
          desktop = "niri";
          extraModules = [ ./nixos/t14p-gen2 ];
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
          stateVersion = "25.05";
          hostname = "desktop";
          noGUI = false;
          proxy.secret = "proxy/clash";
        };
        "chin39@wsl-mini" = helpers.mkHome {
          stateVersion = "25.05";
          username = "chin39";
          hostname = "wsl-mini";
          noGUI = false;
          proxy.secret = "proxy/clash_mini";
          gitProxy = "http://10.0.0.201:7891";
          features = [
            "atuin-sync"
            "dev-tools"
            "rclone"
          ];
        };
        "chin39@wsl" = helpers.mkHome {
          stateVersion = "25.05";
          username = "chin39";
          hostname = "wsl";
          noGUI = false;
          localCaches = [ "home" ];
          proxy.secret = "proxy/clash";
          features = [
            "atuin-sync"
            "dev-tools"
          ];
        };
        "ruowen@ringo" = helpers.mkHome {
          stateVersion = "25.05";
          username = "ruowen";
          hostname = "gentoo";
          noGUI = false;
          isServer = true;
        };
        "chin39@archlinux" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "archlinux";
          isServer = true;
          isPublic = true;
          smallNode = true;
          features = [ "atuin-sync" ];
        };
        "chin39@arch-lxc" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "arch-lxc";
          isServer = true;
          localCaches = [ "home" ];
        };
        "chin39@nixos-lxc" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "nixos-lxc";
          isServer = true;
          localCaches = [ "home" ];
          features = [
            "atuin-sync"
            "dev-tools"
          ];
        };
        "chin39@proxmox" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "proxmox";
          isServer = true;
          localCaches = [ "home" ];
          features = [ "syncthing" ];
        };
        "chin39@arch-vm" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "arch";
          isServer = false;
        };
        "chin39@vm-gentoo" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "vm-gentoo";
          platform = "aarch64-linux";
        };
        "chin39@vm-work" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "work";
          platform = "aarch64-linux";
        };
        "chin39@gentoo-server" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "gentoo-server";
          isServer = true;
          localCaches = [ "home" ];
          features = [ "atuin-sync" ];
        };
        "chin39@vm-nix" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "vm-nix";
          isServer = true;
          noGUI = true;
          localCaches = [ "home" ];
          gitProxy = "http://192.168.0.240:10809";
          features = [
            "atuin-sync"
            "chatgpt-linker-tunnel"
            "dev-tools"
            "nix-gc"
            "rclone"
            "rclone-progress"
            "restic"
            "syncthing"
          ];
        };
        "chin39@macos" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "macos";
          platform = "aarch64-darwin";
          proxy.url = "http://127.0.0.1:10809";
          features = [
            "atuin-sync"
            "syncthing"
          ];
        };
        "chin39@work" = helpers.mkHome {
          stateVersion = "25.05";
          hostname = "work";
          localCaches = [ "home" ];
        };
      };
    };
}
