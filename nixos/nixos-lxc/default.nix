{ config, modulesPath, pkgs, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./proxy.nix
    ./postgresql.nix
  ];

  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = false;
  };

  networking.nameservers = [ "127.0.0.1" ];
  environment.etc."systemd/network/eth0.network.d/10-local-lan.conf".text = ''
    [RoutingPolicyRule]
    To=192.168.0.0/24
    Table=main
    Priority=2500
  '';

  nix.gc = {
    dates = "weekly";
    options = "--delete-older-than 14d";
    randomizedDelaySec = "0";
  };

  users.groups.users.gid = 100;
  users.groups.kvm.gid = 302;
  users.users.chin39 = {
    uid = 1000;
    group = "users";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "docker" "kvm" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICQdeHBZgJNuZKJB06gd3smQHahW9PShg5u2mceb/1Ro chin39@proxy"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  virtualisation.docker.rootless = {
    enable = false;
    setSocketVariable = false;
  };
  programs.fuse = {
    enable = false;
    userAllowOther = false;
  };
  services.envfs.enable = false;
  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = "/var/lib/docker";

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraSetFlags = [ "--accept-routes=true" ];
  };

  services.openssh = {
    openFirewall = true;
    settings = {
      AuthenticationMethods = "publickey";
      PubkeyAuthentication = true;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };

  environment.systemPackages = with pkgs; [
    jq
    python3
    qemu
    acl
    vim
  ];

  environment.etc."tmpfiles.d/static-nodes-permissions.conf".source =
    pkgs.runCommand "static-nodes-permissions.conf" { } ''
      substitute ${config.systemd.package}/example/tmpfiles.d/static-nodes-permissions.conf "$out" \
        --replace-fail 'z /dev/kvm          0666 - kvm -' 'z /dev/kvm          0660 - kvm -'
    '';

  systemd.tmpfiles.rules = [
    "L+ /run/current-system - - - - /nix/var/nix/profiles/system"
  ];
}
