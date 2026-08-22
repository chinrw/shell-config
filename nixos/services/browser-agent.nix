{ pkgs, lib, ... }:
let
  lanAddress = "192.168.0.240";

  # hermes runs as this uid on the host and owns the profile directories. The
  # browser must run as the same uid or it cannot write the profile it is
  # given, and Chromium's sandbox refuses to start as root regardless.
  hermesUid = 987;

  # Same egress proxy flaresolverr.nix pins. Keep the two in step: this host
  # gives bridged containers no direct route out.
  egressProxy = "http://192.168.0.240:10809";

  # Derived from this host's own running container spec rather than copied off
  # the internet, so every one of the 377 syscalls this Docker version grants
  # is preserved exactly; the only delta is the namespace flags Chromium's
  # sandbox needs (NEWUSER/NEWPID/NEWNET/NEWNS) plus an `unshare` rule under
  # the same mask. NEWCGROUP/NEWUTS/NEWIPC stay denied.
  #
  # It is a frozen copy. Docker's builtin default changes across releases and
  # this file will not follow, so re-derive it when Docker is upgraded:
  #   jq '.linux.seccomp' /var/run/docker/containerd/daemon/*/moby/<id>/config.json
  # Symptom of drift is a syscall returning EPERM for no visible reason.
  # Captured from Docker 29.7.2 on 2026-08-17.
  chromiumSeccomp = ./browser-agent/chromium-seccomp.json;

  # Plain pkgs.chromium, deliberately NOT the --no-sandbox wrapper hermes.nix
  # builds for its own consumers. Sandbox policy is this container's job now,
  # which is the whole point of splitting it out.
  browserChromium = pkgs.chromium;

  novncWebRoot = "${pkgs.novnc}/share/webapps/novnc";

  # South Plus is a Chinese board and Baidu Pan is a Chinese SPA; without CJK
  # coverage Chromium renders both as boxes and the operator cannot read the
  # CAPTCHA they are meant to type. Same font set hermes.nix gives its browsers.
  browserFontConfig = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  # Container-internal ports. Every instance gets its own network namespace, so
  # these are identical in all of them and only the published host ports differ.
  cdpPort = 9222;
  vncPort = 5900;
  novncPort = 6080;

  # Chromium ignores --remote-debugging-address and binds DevTools to loopback
  # only, so Docker's port forwarder finds nothing on the container IP. socat
  # bridges the container interface to that loopback listener; the Host header
  # passes through untouched, which keeps Chromium's DNS-rebinding check happy.
  cdpBridgePort = 9223;

  # One long-lived headed Chromium: hermes drives it over CDP while a human can
  # watch and type into the same window over noVNC. That shared window is the
  # requirement CAPTCHA and QR logins impose — a headless browser cannot be
  # handed to a person mid-flow.
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
        pkgs.python3Packages.websockify
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

        # Chromium stamps SingletonLock with "<hostname>-<pid>" and refuses to
        # start when it does not recognise both. A replaced container has a new
        # hostname and its Chromium is pid 1 again, so the stale lock always
        # looks live and every restart would fail. Clearing it is safe because
        # this container is the only writer of the profile and nothing is
        # running yet at this point in the entrypoint.
        rm -f ${profileDir}/Singleton{Lock,Socket,Cookie}

        Xvfb "$DISPLAY" -screen 0 1280x900x24 -nolisten tcp &
        for _ in $(seq 1 40); do
          xdpyinfo >/dev/null 2>&1 && break
          sleep 0.25
        done
        xdpyinfo >/dev/null 2>&1 || { echo "Xvfb failed to become ready" >&2; exit 1; }

        # The VNC port itself is not published, but websockify below bridges it
        # to the LAN, so this session needs a password: without one, anyone on
        # the network can drive a browser that is logged into these sites.
        #
        # VNC's classic auth truncates the secret to 8 characters, so a longer
        # one buys nothing. It is regenerated on every container start and handed
        # over through a 0600 file rather than the command line or the log.
        vnc_password=$(head -c 6 /dev/urandom | base64 | cut -c1-8)
        x11vnc -storepasswd "$vnc_password" /tmp/vncpasswd >/dev/null 2>&1
        printf '%s\n' "$vnc_password" > ${runtimeDir}/vnc-password
        chmod 600 ${runtimeDir}/vnc-password
        unset vnc_password

        x11vnc -display "$DISPLAY" -forever -shared -rfbport ${toString vncPort} \
          -rfbauth /tmp/vncpasswd \
          -listen localhost -no6 -noipv6 -noxdamage -quiet &

        websockify --web=${novncWebRoot} \
          "0.0.0.0:${toString novncPort}" "127.0.0.1:${toString vncPort}" &

        # Reaches Chromium's loopback-only DevTools listener from the container
        # interface. Started before Chromium so no connection races the exec;
        # early connections just fail until Chromium is up, which is what the
        # health check's start period covers.
        socat "TCP-LISTEN:${toString cdpBridgePort},fork,reuseaddr" \
          "TCP:127.0.0.1:${toString cdpPort}" &

        # No --remote-debugging-address: Chromium ignores it and binds loopback
        # regardless, so asking for 0.0.0.0 only misleads the next reader.
        # CDP has no authentication — anything reaching the bridged port owns
        # this browser and every session in the profile. That is the reason the
        # two sites get separate instances rather than separate tabs.
        # hermes-agent reaches the outside through host networking; a bridged
        # container has no such path on this host — direct egress fails for every
        # docker bridge, not just this one. The proxy is the only way out, and
        # Chromium ignores http_proxy in the environment, so it has to be a flag.
        # Baidu still leaves through the host's own address: xray routes
        # geosite:cn direct, so the proxy does not change the egress IP the
        # account is used to.
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

  # One instance per browser profile, because one Chromium process owns exactly
  # one user-data-dir and CDP exposes a single persistent context (contexts[0]);
  # new_context() is incognito and carries no login. "Several profiles in one
  # container" is therefore not expressible — a profile boundary is a container
  # boundary here.
  #
  # This does NOT mean one instance per site. A single contexts[0] holds any
  # number of site logins at once — its cookie jar is per-origin — so `general`
  # below is the default home for new logins and costs nothing to extend: log in
  # through its noVNC desktop and the cookies persist in its profile. Splitting a
  # site out is a Nix change plus a rebuild, so only do it for one of the three
  # reasons the two named instances exist.
  #
  # The split is by trust domain, not by convenience:
  #   - the CDP port has no authentication, so whoever reaches one owns every
  #     origin in that browser. Merged, one unauthenticated port would hold the
  #     forum and a cloud drive with delete authority at the same time;
  #   - the sandbox is what stands between an attacker-controlled forum page and
  #     the profile's cookie database. A renderer escape reads whatever shares
  #     the profile;
  #   - one Chromium per user-data-dir also means one sibling flock. Merged, a
  #     multi-hour South Plus batch serialises every Baidu transfer behind it,
  #     and restarting one site's browser kills the other site's session.
  #
  # Sharing a profile buys exactly one saved QR scan; a dedicated profile
  # persists across container restarts just as well.
  #
  # Names are deliberately asymmetric: the South Plus container keeps the bare
  # `browser-agent` it was created with, because ~38 places across the Hermes
  # skills name that container, its `docker-browser-agent` unit and its runtime
  # directory. Renaming it buys symmetry and risks a stale reference in a skill
  # that decides purchases and deletions. Do not "fix" this without also
  # rewriting those skills.
  instances = {
    southplus = {
      containerName = "browser-agent";
      profileDir = "/var/lib/hermes/workspace/southplus_browser_profile";
      runtimeDir = "/var/lib/hermes/workspace/browser-agent-runtime";
      hostCdpPort = 9222;
      hostNovncPort = 6080;
    };

    baidu = {
      containerName = "browser-agent-baidu";
      # Sibling of the canonical Baidu profile lock,
      # /home/hermes/baidu-share-transfer/.baidu-profile.lock as hermes sees it.
      profileDir = "/var/lib/hermes/home/baidu-share-transfer/.baidu-profile";
      runtimeDir = "/var/lib/hermes/home/baidu-share-transfer/browser-agent-runtime";
      hostCdpPort = 9322;
      hostNovncPort = 6081;
    };

    # Default home for everything that is neither of the above: any other site
    # login goes in contexts[0] alongside the rest, and throwaway scraping uses
    # new_context(), which is incognito and cannot see those logins. Both fit in
    # one instance precisely because the isolation is per-context, not per
    # container. A new service belongs here unless it can destroy something,
    # runs batches long enough to block others on the profile lock, or renders
    # attacker-controlled pages.
    general = {
      containerName = "browser-agent-general";
      profileDir = "/var/lib/hermes/workspace/general_browser_profile";
      runtimeDir = "/var/lib/hermes/workspace/browser-agent-general-runtime";
      hostCdpPort = 9422;
      hostNovncPort = 6082;
    };
  };

  mkInstance =
    site:
    {
      containerName,
      profileDir,
      runtimeDir,
      hostCdpPort,
      hostNovncPort,
    }:
    let
      networkName = containerName;
      entrypoint = mkEntrypoint { inherit site profileDir runtimeDir; };
    in
    {
      # noVNC only. The CDP port is deliberately absent: it is published to
      # 127.0.0.1 and must never be reachable from the LAN.
      networking.firewall.allowedTCPPorts = [ hostNovncPort ];

      virtualisation.oci-containers.containers.${containerName} = {
        image = "ubuntu:24.04";

        # Every binary comes from the host's Nix store, same as hermes-agent, so
        # the base image only supplies a filesystem layout and never needs
        # rebuilding when the browser is updated.
        entrypoint = "${entrypoint}/bin/browser-agent-${site}-entrypoint";

        volumes = [
          "/nix/store:/nix/store:ro"
          "${profileDir}:${profileDir}"
          "${runtimeDir}:${runtimeDir}"
        ];

        ports = [
          # South Plus keeps the conventional 9222; inside, it lands on socat.
          "127.0.0.1:${toString hostCdpPort}:${toString cdpBridgePort}/tcp"
          "${lanAddress}:${toString hostNovncPort}:${toString novncPort}/tcp"
        ];

        log-driver = "journald";

        extraOptions = [
          # Its own network, not the default bridge: flaresolverr sits on that
          # one and Chromium's CDP endpoint accepts any IP-literal Host header,
          # so a shared bridge would let a neighbouring container — including
          # the other browser-agent — drive this browser.
          "--network=${networkName}"
          "--user=${toString hermesUid}:${toString hermesUid}"
          "--security-opt=seccomp=${chromiumSeccomp}"
          # Chromium's renderers use POSIX shared memory heavily; the 64M default
          # is what forces --disable-dev-shm-usage elsewhere in this config.
          "--shm-size=1g"
          # Probes through the socat bridge, not Chromium directly, so the check
          # covers the whole path hermes actually connects over.
          "--health-cmd=${pkgs.curl}/bin/curl -fsS --max-time 3 http://127.0.0.1:${toString cdpBridgePort}/json/version || exit 1"
          "--health-interval=30s"
          "--health-timeout=5s"
          "--health-retries=3"
          "--health-start-period=30s"
        ];
      };

      # Both must exist and belong to hermesUid before the container starts:
      # Docker would otherwise create the bind-mount sources as root, and a
      # container running as 987 cannot write its own profile. Existing
      # profiles are already 0700 hermes:hermes, so this is a no-op for them.
      systemd.tmpfiles.rules = [
        "d ${profileDir} 0700 ${toString hermesUid} ${toString hermesUid} -"
        "d ${runtimeDir} 0700 ${toString hermesUid} ${toString hermesUid} -"
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
        serviceConfig = {
          Restart = lib.mkOverride 90 "on-failure";
          RestartSec = "10s";
        };
      };
    };
in
lib.mkMerge (
  [
    {
      virtualisation.docker.enable = lib.mkDefault true;
      virtualisation.oci-containers.backend = lib.mkDefault "docker";
    }
  ]
  ++ lib.mapAttrsToList mkInstance instances
)

# Bridge networking, not host: these containers render untrusted pages, and on
# host networking they would also reach every host-local service (LANraragi,
# jellyfin, the hermes gateway) — and each other's CDP port. Published ports are
# the only way in, and NAT still gives each browser its egress.
