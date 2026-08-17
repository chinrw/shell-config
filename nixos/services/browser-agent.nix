{ pkgs, lib, ... }:
let
  cdpPort = 9222;
  novncPort = 6080;
  vncPort = 5900;
  lanAddress = "192.168.0.240";

  # hermes runs as this uid on the host and owns the profile directory. The
  # browser must run as the same uid or it cannot write the profile it is
  # given, and Chromium's sandbox refuses to start as root regardless.
  hermesUid = 987;

  profileDir = "/var/lib/hermes/workspace/southplus_browser_profile";

  # Same egress proxy flaresolverr.nix pins. Keep the two in step: this host
  # gives bridged containers no direct route out.
  egressProxy = "http://192.168.0.240:10809";

  # Where the container hands the per-start VNC password back to the operator.
  runtimeDir = "/var/lib/hermes/workspace/browser-agent-runtime";

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

  # South Plus is a Chinese board; without CJK coverage Chromium renders the
  # page as boxes and the operator cannot read the CAPTCHA they are meant to
  # type. Same font set hermes.nix gives its own browsers.
  browserFontConfig = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
    ];
  };

  # Chromium ignores --remote-debugging-address and binds DevTools to loopback
  # only, so Docker's port forwarder finds nothing on the container IP. socat
  # bridges the container interface to that loopback listener; the Host header
  # passes through untouched, which keeps Chromium's DNS-rebinding check happy.
  cdpBridgePort = 9223;

  # One long-lived headed Chromium: hermes drives it over CDP while a human can
  # watch and type into the same window over noVNC. That shared window is the
  # requirement CAPTCHA and QR logins impose — a headless browser cannot be
  # handed to a person mid-flow.
  entrypoint = pkgs.writeShellApplication {
    name = "browser-agent-entrypoint";
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
      # this browser and every session in the profile.
      # hermes-agent reaches the outside through host networking; a bridged
      # container has no such path on this host — direct egress fails for every
      # docker bridge, not just this one. The proxy is the only way out, and
      # Chromium ignores http_proxy in the environment, so it has to be a flag.
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
in
{
  virtualisation.docker.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = lib.mkDefault "docker";

  # noVNC only. The CDP port is deliberately absent: it is published to
  # 127.0.0.1 and must never be reachable from the LAN.
  networking.firewall.allowedTCPPorts = [ novncPort ];

  virtualisation.oci-containers.containers."browser-agent" = {
    image = "ubuntu:24.04";

    # Every binary comes from the host's Nix store, same as hermes-agent, so
    # the base image only supplies a filesystem layout and never needs
    # rebuilding when the browser is updated.
    entrypoint = "${entrypoint}/bin/browser-agent-entrypoint";

    volumes = [
      "/nix/store:/nix/store:ro"
      "${profileDir}:${profileDir}"
      "${runtimeDir}:${runtimeDir}"
    ];

    ports = [
      # Host-side port keeps the conventional 9222; inside, it lands on socat.
      "127.0.0.1:${toString cdpPort}:${toString cdpBridgePort}/tcp"
      "${lanAddress}:${toString novncPort}:${toString novncPort}/tcp"
    ];

    log-driver = "journald";

    extraOptions = [
      # Its own network, not the default bridge: flaresolverr sits on that one
      # and Chromium's CDP endpoint accepts any IP-literal Host header, so a
      # shared bridge would let a neighbouring container drive this browser.
      "--network=browser-agent"
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

  systemd.tmpfiles.rules = [
    "d ${runtimeDir} 0700 ${toString hermesUid} ${toString hermesUid} -"
  ];

  systemd.services."docker-network-browser-agent" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker network inspect browser-agent >/dev/null 2>&1 \
        || docker network create browser-agent
    '';
    partOf = [ "docker-browser-agent.service" ];
    wantedBy = [ "docker-browser-agent.service" ];
  };

  systemd.services."docker-browser-agent" = {
    after = [ "docker-network-browser-agent.service" ];
    requires = [ "docker-network-browser-agent.service" ];
    unitConfig.RequiresMountsFor = [ profileDir ];
    serviceConfig = {
      Restart = lib.mkOverride 90 "on-failure";
      RestartSec = "10s";
    };
  };

  # Bridge networking, not host: this container renders untrusted pages, and on
  # host networking it would also reach every host-local service (LANraragi,
  # jellyfin, the hermes gateway). Published ports are the only way in, and
  # NAT still gives the browser its egress.
}
