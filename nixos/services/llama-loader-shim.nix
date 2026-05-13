{ pkgs, ... }:
# llama-loader-shim — transparent /models/load injector.
#
# Sits between Hermes (or any OpenAI-compatible client) and the upstream
# llama.cpp server on the Windows box. Whenever a chat/completion arrives
# for a model that isn't currently loaded, the shim issues
# `POST /models/load` on the upstream first, so requests stop 400-ing
# with "model is not loaded". Cached state collapses the steady-state to
# a single load per swap; cache misses (server restart, idle eviction)
# are recovered by one forced retry on the first 400.
#
# Why this exists: `llama-server` was launched with
# --no-models-autoload + --models-max 1 (see models.ini on the Windows
# host), which means clients must explicitly POST /models/load before
# any chat completion will succeed. Hermes' `/model` picker only changes
# routing, not server-side load state, so without this shim "switch and
# go" doesn't work — switching to an un-loaded model fails until you
# curl /models/load by hand.
#
# Source: nixos/services/llama-loader-shim/shim.py.
let
  upstreamUrl = "http://192.168.0.101:8087";
  # Loopback-only — the only intended client is hermes-agent on this
  # same host, which runs with `--network=host` (hardcoded in the
  # upstream NixOS module, hermes-agent/nix/nixosModules.nix:942), so
  # 127.0.0.1 inside the container is this host's loopback. Binding
  # 0.0.0.0 here would just leak the shim onto the LAN with no real
  # consumer.
  bindHost = "127.0.0.1";
  bindPort = 8088;

  shim = pkgs.writers.writePython3Bin "llama-loader-shim" {
    libraries = [ pkgs.python3Packages.aiohttp ];
    flakeIgnore = [
      "E501" # long URLs / log lines
      "W503" # line break before operator (PEP 8 / black disagreement)
    ];
  } (builtins.readFile ./llama-loader-shim/shim.py);
in
{
  systemd.services.llama-loader-shim = {
    description = "Transparent /models/load injector for upstream llama.cpp";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      UPSTREAM_URL = upstreamUrl;
      BIND_HOST = bindHost;
      BIND_PORT = toString bindPort;
      # 90 s comfortably covers cold-loading a 17 GB Q4 27B onto a 32 GB
      # GPU (typical 20–40 s) plus vision-swap overhead (mmproj adds
      # ~1 GB and ~5 s).
      LOAD_TIMEOUT = "90";
    };

    serviceConfig = {
      ExecStart = "${shim}/bin/llama-loader-shim";
      Restart = "always";
      RestartSec = 5;

      # Sandbox — the shim is a stateless HTTP proxy that talks to one
      # upstream and listens on one port. Lock it down aggressively.
      DynamicUser = true;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];
    };
  };

}
