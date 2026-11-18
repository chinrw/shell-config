{
  config,
  inputs,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./derper.nix
  ];

  networking.hostName = "aliyun";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  networking.usePredictableInterfaceNames = false;
  networking.nameservers = [
    "100.100.2.136"
    "100.100.2.138"
  ];
  services.resolved.enable = true;
  systemd.network.networks."10-aliyun" = {
    matchConfig.MACAddress = "00:16:3e:4b:33:d7";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
    dhcpV4Config = {
      ClientIdentifier = "mac";
      RouteMetric = 100;
      UseDNS = true;
      UseRoutes = true;
      UseMTU = true;
    };
  };

  services.openssh = {
    settings = {
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
    };
    extraConfig = ''
      Match User tunnel-internal
          AuthenticationMethods publickey
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          AllowTcpForwarding remote
          PermitListen 127.0.0.1:22022
          GatewayPorts no
          # Deny shell, command and SFTP sessions while keeping forwarding available.
          MaxSessions 0
          AllowStreamLocalForwarding no
          PermitTunnel no
          AllowAgentForwarding no
          X11Forwarding no
      Match all
    '';
  };
  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.${username}.openssh.authorizedKeys.keys;
  users.users.${username} = {
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };
  users.groups.tunnel-internal = { };
  users.users.tunnel-internal = {
    isSystemUser = true;
    group = "tunnel-internal";
    description = "Reverse SSH tunnel";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG7luDlJ1tZKPydiigtPlsNHrJh7zULqCorRftpJP/I5 aliyun-tunnel"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.tailscale = {
    enable = true;
    package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.tailscale;
    openFirewall = true;
    useRoutingFeatures = "none";
    extraSetFlags = [
      "--hostname=aliyun"
      "--ssh=false"
      "--accept-dns=false"
      "--accept-routes=false"
      "--relay-server-port=40000"
    ];
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.allowedUDPPorts = [ 40000 ];

  # The tailnet disables the CGNAT drop rule for this host. Reject sources whose
  # return route uses another interface while allowing Alibaba's internal services.
  networking.firewall.checkReversePath = "strict";
  boot.kernel.sysctl."net.ipv4.conf.eth0.rp_filter" = 1;

  nix.settings = {
    substituters = [
      "https://mirrors.ustc.edu.cn/nix-channels/store?priority=39"
      "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    ];
    require-sigs = true;
    max-jobs = 1;
    cores = 2;
    connect-timeout = 5;
    stalled-download-timeout = 15;
  };
}
