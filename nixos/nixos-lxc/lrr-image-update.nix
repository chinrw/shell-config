{ config, lib, pkgs, ... }:
let
  deployedImage = config.virtualisation.oci-containers.containers.lanraragi.image;
in
{
  systemd.services.lrr-image-update-check = {
    description = "Check for a new LANraragi image without deploying it";
    wants = [ "network-online.target" "xray.service" ];
    after = [ "network-online.target" "xray.service" ];
    environment = {
      http_proxy = config.networking.proxy.default;
      https_proxy = config.networking.proxy.default;
      no_proxy = config.networking.proxy.noProxy;
    };
    path = with pkgs; [ skopeo jq coreutils ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "lrr-image-update";
      TimeoutStartSec = "3min";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      UMask = "0022";
    };
    script = ''
      set -euo pipefail
      deployed=${lib.escapeShellArg deployedImage}
      current="''${deployed##*@}"
      latest=$(skopeo --command-timeout 2m inspect --retry-times 2 \
        --format '{{.Digest}}' docker://docker.io/difegue/lanraragi:latest)
      [[ "$latest" =~ ^sha256:[0-9a-f]{64}$ ]]
      jq -n --arg checkedAt "$(date -u +%FT%TZ)" \
        --arg image "$deployed" --arg current "$current" --arg latest "$latest" \
        '{checkedAt:$checkedAt,image:$image,currentDigest:$current,latestDigest:$latest,updateAvailable:($current!=$latest)}' \
        > "$STATE_DIRECTORY/status.json.tmp"
      mv "$STATE_DIRECTORY/status.json.tmp" "$STATE_DIRECTORY/status.json"
      if [[ "$current" != "$latest" ]]; then
        echo "LANraragi update available: $current -> $latest. Deployment requires confirmation."
      else
        echo "LANraragi is up to date: $current"
      fi
    '';
  };
  systemd.timers.lrr-image-update-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };
}
