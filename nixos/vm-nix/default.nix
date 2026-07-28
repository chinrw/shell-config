{
  inputs,
  config,
  lib,
  pkgs,
  hostname,
  username,
  ...
}:
let
  sharedGroup = "users";
  # Backport Xray #6095; drop when stable Nixpkgs includes it.
  xrayPatched = pkgs.xray.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../../patches/xray/9d9eaf3-close-xhttp-body.patch
    ];
  });
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
        lib
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
    ./oom-guard.nix
    ./zram.nix
    ../services/hermes.nix
    ../services/llama-loader-shim.nix
    ../services/flaresolverr.nix
    ../services/tailscale-exit-proxy.nix
    ../services/stocks-proxy.nix
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
    # Resolve through the local AdGuard instead of the router. 192.168.0.1,
    # AliDNS and AdGuard's previous upstreams all answer
    # wss-primary.slack.com and edgeapi.slack.com with 112.121.185.234, a
    # sinkhole that 302s to baidu.com under a certificate whose only SAN is
    # that IP, so Slack Socket Mode fails TLS hostname verification and hermes
    # receives no Slack events. slack.com, api.slack.com, files.slack.com and
    # wss-backup.slack.com still resolve correctly, which is why the REST API
    # kept working and only the websocket broke. Direct connections to Slack's
    # real addresses verify fine, so only resolution is affected.
    #
    # 1.1.1.1 is second so a stopped AdGuard cannot take DNS down with it.
    nameservers = [
      "127.0.0.1"
      "1.1.1.1"
    ];
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
      8443 # tt-sync

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
      "github-runners/stocks" = {
        restartUnits = [
          "github-runner-stocks-1.service"
          "github-runner-stocks-2.service"
          "github-runner-stocks-3.service"
          "github-runner-stocks-4.service"
          "github-runner-stocks-5.service"
          "github-runner-stocks-6.service"
        ];
      };
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

  # The settings themselves live in the sops secret above. Worth knowing without
  # decrypting it: proxied traffic is routed to the `proxy-balancer` balancer
  # rather than straight to the `proxy` outbound. The balancer selects only
  # `proxy` and carries `fallbackTag = "fallback-socks"`, a SOCKS5 outbound
  # pointing at the Windows box (192.168.0.101:7891, the same mixed-port proxy
  # wsl.nix uses). `observatory` probes `proxy` every 30s against
  # https://www.google.com/generate_204; when that probe fails the balancer has
  # no live candidate and every proxied rule — including AdGuard's DNS path
  # through dnscrypt-proxy — falls through to the LAN proxy until it recovers.
  # Strict priority, not load balancing: an outbound the observatory has no
  # verdict on yet counts as alive, so a fresh start still uses `proxy`.
  services.xray = {
    enable = true;
    package = xrayPatched;
    settingsFile = "/etc/xray/xray_client.conf";
  };

  services = {
    qemuGuest.enable = true;

    # Encrypted upstream for AdGuard. AdGuard cannot do this itself: dnsproxy
    # dials upstream_dns with no proxy support, and every encrypted transport
    # is blocked on the direct path, so DoH has to terminate in a forwarder
    # that can use xray. Over the SOCKS inbound it reaches Cloudflare and
    # returns correct answers for the hijacked Slack names.
    #
    # The stamp is the official cloudflare entry from public-resolvers.md,
    # inlined with sources cleared so startup does not depend on fetching the
    # resolver list through the tunnel.
    dnscrypt-proxy = {
      enable = true;
      settings = {
        listen_addresses = [ "127.0.0.1:5353" ];
        server_names = [ "cloudflare" ];
        proxy = "socks5://127.0.0.1:10808";

        cache = true;
        cache_size = 4096;

        sources = { };
        static.cloudflare.stamp =
          "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
      };
    };
    adguardhome = {
      enable = true;
      openFirewall = true;
      settings = {
        # Covers AdGuard's own HTTP client (filter and version fetches) only.
        # dnsproxy dials upstream_dns without it, so an https:// upstream would
        # be attempted directly and time out.
        http_proxy = "http://127.0.0.1:10809";

        dns = {
          # dnscrypt-proxy2, so queries leave this host encrypted and are
          # resolved at the tunnel exit rather than by the hijacking chain.
          #
          # fallback_dns is plaintext on purpose: it keeps DNS answering if
          # dnscrypt-proxy stops or its upstream breaks, at the cost of being
          # silent when it takes over. AdGuard's query log records the
          # answering upstream per query, so `127.0.0.1:5353` there means the
          # encrypted path is live and `1.1.1.1:53` means it is not.
          # `systemctl is-active dnscrypt-proxy2` catches the crashed case but
          # not a running forwarder whose own upstream is failing.
          upstream_dns = [
            "127.0.0.1:5353"
          ];
          bootstrap_dns = [
            "1.1.1.1"
            "8.8.8.8"
          ];
          fallback_dns = [
            "1.1.1.1"
            "8.8.8.8"
          ];
        };
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
