{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = false;
  };

  # envfs provides /bin only after init starts. Cold boot needs a store interpreter.
  system.build.installBootLoader = lib.mkForce (
    pkgs.replaceVarsWith {
      src = pkgs.runCommand "lxc-init-script-builder.sh" { } ''
        substitute ${
          builtins.path {
            path = modulesPath + "/system/boot/loader/init-script/init-script-builder.sh";
            name = "init-script-builder.sh";
          }
        } "$out" \
          --replace-fail 'echo "#!/bin/sh"' 'echo "#!${pkgs.bash}/bin/sh"'
      '';
      isExecutable = true;
      replacements = {
        inherit (pkgs) bash;
        inherit (config.system.nixos) distroName;
        path = lib.makeBinPath [
          pkgs.coreutils
          pkgs.gnused
          pkgs.gnugrep
        ];
      };
    }
  );

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
    linger = true;
    group = "users";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
      "kvm"
    ];
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
    enable = true;
    userAllowOther = false;
  };
  services.envfs.enable = true;
  systemd.settings.Manager.DefaultLimitNOFILE = "1024:1048576";
  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = "/var/lib/docker";

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = lib.mkDefault "client";
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
    pkgs.runCommand "static-nodes-permissions.conf" { }
      ''
        substitute ${config.systemd.package}/example/tmpfiles.d/static-nodes-permissions.conf "$out" \
          --replace-fail 'z /dev/kvm          0666 - kvm -' 'z /dev/kvm          0660 - kvm -'
      '';

  systemd.tmpfiles.rules = [
    "L+ /run/current-system - - - - /nix/var/nix/profiles/system"
  ];
}
