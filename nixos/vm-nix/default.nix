{
  inputs,
  config,
  pkgs,
  hostname,
  username,
  ...
}:
let
  sharedGroup = "users";
in
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-amd
    ./hardware.nix
    ./wireguard.nix
    ./container/jellyfin.nix
    ../services/github-runners.nix
    ../services/samba/wsl-server.nix
    (import ../services/aria2.nix {
      inherit
        config
        pkgs
        username
        sharedGroup
        ;
    })
    ../services/qbittorrent.nix
    ../services/cachix-deploy.nix
    ../services/nix-serve.nix
    ../services/factorio.nix
    ./kernel.nix
    ../services/hermes.nix
    ../services/llama-loader-shim.nix
    ../services/flaresolverr.nix
    ../services/tailscale-exit-proxy.nix
    # ./rclone.nix
    # ./proxy.nix
  ];

  users.users.chin39 = {
    isNormalUser = true;
    description = "chin39";
    linger = true;
    extraGroups = [
      "networkmanager"
      "docker"
      "wheel"
      "aria2"
      "media"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = [ config.sops.secrets.ssh_pub_key.path ];
  };

  networking = {
    interfaces = {
      ens18 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "192.168.0.240";
            prefixLength = 24;
          }
        ];
      };
    };
    defaultGateway = {
      address = "192.168.0.1";
      interface = "ens18";
    };
    hostName = hostname;
    networkmanager.enable = true;
    proxy.default = "http://192.168.0.240:10809";
    proxy.noProxy = "10.0.0.0/24,192.168.0.0/24,127.0.0.1,localhost,.localdomain";
    nameservers = [ "192.168.0.1" ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [

      # Alist firewall port
      5244
      5246
      5432

      5000 # local binary cache
      5001 # test webserver1
      5002 # test webserver2
      7892 # AutoBangumi

      8000
      8888 # kik

      8765 # local python testing web
      8787
      8096 # jellyfin

      10808
      10809

      8384 # syncthing web GUI
      22000 # syncthing sync protocol
    ];
    allowedUDPPorts = [
      53
      22000 # syncthing QUIC sync
      21027 # syncthing local discovery
      7359 # jellyfin client autodiscovery
      1900 # SSDP / DLNA
    ];
    allowedUDPPortRanges = [
      # { from = 4000; to = 4007; }
      # { from = 8000; to = 8010; }
    ];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.tpm2.enable = false;

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "C.UTF-8";
    LC_IDENTIFICATION = "C.UTF-8";
    LC_MEASUREMENT = "C.UTF-8";
    LC_MONETARY = "C.UTF-8";
    LC_NAME = "C.UTF-8";
    LC_NUMERIC = "C.UTF-8";
    LC_PAPER = "C.UTF-8";
    LC_TELEPHONE = "C.UTF-8";
    LC_TIME = "C.UTF-8";
  };

  sops = {
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      "wg-vm-nix/privatekey" = { };
      "ssh_pub_key" = { };
      "access-tokens" = { };
      "github-runners/Constantinople" = { };
    };
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--netfilter-mode=nodivert"
      "--advertise-exit-node"
    ];
  };
  sops.secrets."xray" = {
    owner = "root";
    sopsFile = ../../secrets/xray.conf;
    path = "/etc/xray/xray_client.conf";
    format = "binary";
  };

  services.xray = {
    enable = true;
    settingsFile = "/etc/xray/xray_client.conf";
  };

  services = {
    qemuGuest.enable = true;
    adguardhome = {
      enable = true;
      openFirewall = true;
      settings = {
        http_proxy = "http://127.0.0.1:10809";
      };
    };
    # open-webui = {
    #   enable = true;
    #   package = pkgs.stable.open-webui;
    #   host = "192.168.0.240";
    #   environment = {
    #     http_proxy = "http://192.168.0.240:10809";
    #     https_proxy = "http://192.168.0.240:10809";
    #   };
    # };

    # kavita = {
    #   enable = true;
    #   tokenKeyFile = "/etc/nixos/secrets/kavita_token.key";
    #   # make sure the service user can read the key
    # };
    # lanraragi = {
    #   enable = true;
    #   package = pkgs.lanraragi;
    #   port = 3001;
    # };

  };
  # users.users.kavita.extraGroups = [ "kavita" ];

  environment.systemPackages = with pkgs; [
    cifs-utils
    android-tools
    python3
    nftables
  ];

  # Host ZFS pool shared into this VM via virtiofs. This VM runs on the
  # Proxmox host that owns the pool, so we use the shared-memory virtio
  # transport instead of SMB-over-TCP to the host — no network stack, no
  # credentials, no multichannel. The device string "data" is the virtiofs
  # mount tag, which must match the Proxmox directory-mapping id (dirid=data)
  # attached to this VM's hardware.
  #
  # Permissions: virtiofs passes host uid/gid through verbatim (no CIFS-style
  # uid=/gid= remapping). The host dataset (elysion/data, acltype=posixacl)
  # carries setgid dirs + POSIX default ACLs granting group 100 (${sharedGroup})
  # rwx, and the device is attached with expose-acl=1 — so files created by
  # chin39, aria2, or the factorio DynamicUser (all in `${sharedGroup}`) stay
  # group-writable for the others regardless of the writer's umask. See
  # nixos/services/factorio.nix for the group-permission note.
  fileSystems."/mnt/data" = {
    device = "data";
    fsType = "virtiofs";
    options = [
      "nofail"
      "x-systemd.automount" # lazy-mount on first access
    ];
    neededForBoot = false;
  };

  fileSystems."/mnt/autofs/data" = {
    device = "10.0.0.254:/volume1/Data";
    fsType = "nfs4";
    options = [
      "noauto"
      "x-systemd.requires=wireguard-wg0-peer-arch-synology-refresh.service"
      "x-systemd.after=wireguard-wg0-peer-arch-synology-refresh.service"
      "noatime"
      "nofail"
      "_netdev"
      "x-systemd.automount"
    ];
    neededForBoot = false;
  };

  systemd.services.lanraragi.environment = {
    http_proxy = "http://192.168.0.254:10809";
    https_proxy = "http://192.168.0.254:10809";
  };

}
