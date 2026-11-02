{ ... }:
{
  imports = [ ../services/browser-agent.nix ];

  services.browser-agent = {
    enable = true;
    listenAddress = "192.168.0.240";
    # Match Hermes' profile ownership; Chromium cannot run its sandbox as root.
    uid = 987;
    # Bridged containers on this host need the proxy for outbound connections.
    proxy = "http://192.168.0.240:10809";

    # Separate profiles keep CDP authority, profile locks and restarts independent.
    instances = {
      southplus = {
        # Hermes consumers depend on this historical container name.
        containerName = "browser-agent";
        profileDir = "/var/lib/hermes/workspace/southplus_browser_profile";
        runtimeDir = "/var/lib/hermes/workspace/browser-agent-runtime";
        cdpPort = 9222;
        novncPort = 6080;
      };
      baidu = {
        containerName = "browser-agent-baidu";
        profileDir = "/var/lib/hermes/home/baidu-share-transfer/.baidu-profile";
        runtimeDir = "/var/lib/hermes/home/baidu-share-transfer/browser-agent-runtime";
        cdpPort = 9322;
        novncPort = 6081;
      };
      general = {
        containerName = "browser-agent-general";
        profileDir = "/var/lib/hermes/workspace/general_browser_profile";
        runtimeDir = "/var/lib/hermes/workspace/browser-agent-general-runtime";
        cdpPort = 9422;
        novncPort = 6082;
        cdpAllowedSources = [
          "192.168.0.231"
          "192.168.0.242"
        ];
        proxyBypass = [ "192.168.0.242" ];
      };
    };
  };
}
