{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.browser-agent;
  lanAddress = cfg.listenAddress;

  browserUid = cfg.uid;

  egressProxy = cfg.proxy;

  # Chromium needs additional namespace syscalls to keep its sandbox enabled.
  # This policy snapshots Docker defaults and must be reviewed on Docker upgrades.
  chromiumSeccomp = ./browser-agent/chromium-seccomp.json;

  # Use Chromium directly; wrappers that add --no-sandbox disable its renderer sandbox.
  browserChromium = pkgs.chromium;

  # x11vnc handles WebSockets, so only noVNC static assets are needed.
  novncWebRoot = pkgs.runCommand "browser-agent-novnc-${pkgs.novnc.version}" { } ''
    mkdir -p "$out"
    cp -r ${pkgs.novnc.src}/{app,core,po,vendor,vnc.html,vnc_lite.html} "$out/"
  '';

  # CJK fonts keep Chinese login prompts and CAPTCHAs readable.
  browserFontConfig = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  cdpPort = 9222;
  vncPort = 5900;
  novncPort = 6080;

  novncConfig = pkgs.writeText "browser-agent-Caddyfile" ''
    {
      admin off
      auto_https off
      persist_config off
    }

    :${toString novncPort} {
      bind 0.0.0.0
      @vnc header Upgrade websocket
      handle @vnc {
        reverse_proxy 127.0.0.1:${toString vncPort}
      }
      handle {
        root * ${novncWebRoot}
        file_server {
          index vnc.html
        }
      }
    }
  '';

  # Chromium ignores --remote-debugging-address and binds DevTools to loopback.
  # Keep socat to make that listener reachable from Docker's port forwarding.
  cdpBridgePort = 9223;

  mkEntrypoint =
    {
      site,
      profileDir,
      runtimeDir,
    }:
    pkgs.writeShellApplication {
      name = "browser-agent-${site}-entrypoint";
      runtimeInputs = [
        pkgs.xvfb
        pkgs.xdpyinfo
        pkgs.x11vnc
        pkgs.caddy
        pkgs.coreutils
        pkgs.socat
        browserChromium
      ];
      text = ''
        set -euo pipefail
        umask 077

        export DISPLAY=":99"
        export HOME=/tmp/browser-agent-home
        export FONTCONFIG_FILE=${browserFontConfig}
        mkdir -p "$HOME"

        # A replaced container has a different hostname, invalidating Chromium locks.
        # Only this container may write the profile when these are removed.
        rm -f ${profileDir}/Singleton{Lock,Socket,Cookie}

        Xvfb "$DISPLAY" -screen 0 1280x900x24 -nolisten tcp &
        for _ in $(seq 1 40); do
          xdpyinfo >/dev/null 2>&1 && break
          sleep 0.25
        done
        xdpyinfo >/dev/null 2>&1 || { echo "Xvfb failed to become ready" >&2; exit 1; }

        # LAN users can control logged-in sessions, so VNC requires authentication.
        # Classic VNC uses only eight password characters; keep the secret out of logs.
        vnc_password=$(head -c 6 /dev/urandom | base64 | cut -c1-8)
        x11vnc -storepasswd "$vnc_password" /tmp/vncpasswd >/dev/null 2>&1
        printf '%s\n' "$vnc_password" > ${runtimeDir}/vnc-password
        chmod 600 ${runtimeDir}/vnc-password
        unset vnc_password

        x11vnc -display "$DISPLAY" -forever -shared -rfbport ${toString vncPort} \
          -rfbauth /tmp/vncpasswd \
          -listen localhost -no6 -noipv6 -noxdamage -quiet &

        caddy run --config ${novncConfig} --adapter caddyfile &

        socat "TCP-LISTEN:${toString cdpBridgePort},fork,reuseaddr" \
          "TCP:127.0.0.1:${toString cdpPort}" &

        # Keep a headed browser so noVNC can complete logins in the same session.
        # Chromium ignores http_proxy; configure its proxy explicitly.
        exec chromium \
          --user-data-dir=${profileDir} \
          --proxy-server=${egressProxy} \
          --proxy-bypass-list="127.0.0.1;localhost" \
          --remote-debugging-port=${toString cdpPort} \
          --disable-blink-features=AutomationControlled \
          --window-size=1280,900 \
          --window-position=0,0 \
          --no-first-run \
          --no-default-browser-check \
          about:blank
      '';
    };

  mkInstance =
    site: instance:
    let
      inherit (instance) containerName profileDir runtimeDir;
      hostCdpPort = instance.cdpPort;
      hostNovncPort = instance.novncPort;
      networkName = containerName;
      cdpChain = "cdp-${containerName}";
      entrypoint = mkEntrypoint { inherit site profileDir runtimeDir; };
    in
    {
      networking.firewall.allowedTCPPorts = [ hostNovncPort ];

      virtualisation.oci-containers.containers.${containerName} = {
        image = "ubuntu:24.04";

        entrypoint = "${entrypoint}/bin/browser-agent-${site}-entrypoint";

        volumes = [
          "/nix/store:/nix/store:ro"
          "${profileDir}:${profileDir}"
          "${runtimeDir}:${runtimeDir}"
        ];

        ports = [
          "127.0.0.1:${toString hostCdpPort}:${toString cdpBridgePort}/tcp"
          "${lanAddress}:${toString hostNovncPort}:${toString novncPort}/tcp"
        ]
        ++ lib.optional (
          instance.cdpAllowedSource != null
        ) "${lanAddress}:${toString hostCdpPort}:${toString cdpBridgePort}/tcp";

        log-driver = "journald";

        extraOptions = [
          # Separate bridges prevent other containers from reaching unauthenticated CDP.
          # Host networking would also expose host-local services and sibling CDP ports
          # to the browser, so it must not be used to work around egress problems.
          "--network=${networkName}"
          "--user=${toString browserUid}:${toString browserUid}"
          "--security-opt=seccomp=${chromiumSeccomp}"
          # Docker's default 64 MiB is too small for Chromium renderer shared memory.
          "--shm-size=1g"
          # Probe through socat so readiness covers the path used by CDP clients.
          "--health-cmd=${pkgs.curl}/bin/curl -fsS --max-time 3 http://127.0.0.1:${toString cdpBridgePort}/json/version || exit 1"
          "--health-interval=30s"
          "--health-timeout=5s"
          "--health-retries=3"
          "--health-start-period=30s"
        ];
      };

      # Create these before Docker can create root-owned bind-mount directories.
      systemd.tmpfiles.rules = [
        "d ${profileDir} 0700 ${toString browserUid} ${toString browserUid} -"
        "d ${runtimeDir} 0700 ${toString browserUid} ${toString browserUid} -"
      ];

      systemd.services."docker-network-${networkName}" = {
        path = [ pkgs.docker ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          docker network inspect ${networkName} >/dev/null 2>&1 \
            || docker network create ${networkName}
        '';
        partOf = [ "docker-${containerName}.service" ];
        wantedBy = [ "docker-${containerName}.service" ];
      };

      systemd.services."docker-${containerName}" = {
        after = [ "docker-network-${networkName}.service" ];
        requires = [ "docker-network-${networkName}.service" ];
        unitConfig.RequiresMountsFor = [ profileDir ];
        # Filter before Docker's DNAT, which bypasses the host INPUT firewall.
        # Restore replaces this chain atomically when the allowed source changes;
        # retaining it on stop protects CDP if container cleanup fails.
        preStart = ''
          ${pkgs.iptables}/bin/iptables-restore -w --noflush <<'RULES'
          *raw
          :${cdpChain} - [0:0]
          -A ${cdpChain} -d ${lanAddress} -p tcp --dport ${toString hostCdpPort} ${
            lib.optionalString (instance.cdpAllowedSource != null) "! -s ${instance.cdpAllowedSource}"
          } -j DROP
          COMMIT
          RULES
          ${pkgs.iptables}/bin/iptables -w -t raw -C PREROUTING -j ${cdpChain} 2>/dev/null || \
            ${pkgs.iptables}/bin/iptables -w -t raw -I PREROUTING -j ${cdpChain}
        '';
        serviceConfig = {
          Restart = lib.mkOverride 90 "on-failure";
          RestartSec = "10s";
        };
      };
    };
  instanceConfigs = lib.mapAttrsToList mkInstance cfg.instances;
in
{
  options.services.browser-agent = {
    enable = lib.mkEnableOption "persistent browsers with CDP and noVNC access";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      description = "Host IPv4 address for noVNC and source-restricted LAN CDP access.";
    };
    uid = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Non-root UID and GID that own the browser profiles and runtime directories.";
    };
    proxy = lib.mkOption {
      type = lib.types.str;
      description = "Outbound proxy passed to Chromium.";
    };
    instances = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            containerName = lib.mkOption {
              type = lib.types.str;
              description = "Docker container name, also used for its network and systemd unit.";
            };
            profileDir = lib.mkOption {
              type = lib.types.str;
              description = "Persistent Chromium profile directory on the host.";
            };
            runtimeDir = lib.mkOption {
              type = lib.types.str;
              description = "Host directory containing the generated vnc-password file.";
            };
            cdpPort = lib.mkOption {
              type = lib.types.port;
              description = "Host CDP port, always available on IPv4 localhost.";
            };
            novncPort = lib.mkOption {
              type = lib.types.port;
              description = "Host noVNC port on listenAddress.";
            };
            cdpAllowedSource = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Remote IPv4 address allowed to use LAN CDP. Null keeps CDP on localhost only.";
            };
          };
        }
      );
      description = "Browsers with separate persistent profiles and isolated Docker networks.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: instance: {
      assertion = builtins.stringLength "cdp-${instance.containerName}" <= 28;
      message = "browser-agent instance ${name}: containerName must be at most 24 characters so its CDP firewall chain fits iptables' 28-character limit.";
    }) cfg.instances;

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    virtualisation.oci-containers.containers = lib.mkMerge (
      map (c: c.virtualisation.oci-containers.containers) instanceConfigs
    );
    networking.firewall.allowedTCPPorts = lib.concatMap (
      c: c.networking.firewall.allowedTCPPorts
    ) instanceConfigs;
    systemd.services = lib.mkMerge (map (c: c.systemd.services) instanceConfigs);
    systemd.tmpfiles.rules = lib.concatMap (c: c.systemd.tmpfiles.rules) instanceConfigs;
  };
}
