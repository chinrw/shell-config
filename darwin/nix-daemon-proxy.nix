{ ... }:
let
  proxyURL = "http://127.0.0.1:10809";
  noProxy = (import ../lib/proxy.nix).noProxy;
in
{
  launchd.daemons.nix-daemon.serviceConfig.EnvironmentVariables = {
    http_proxy = proxyURL;
    https_proxy = proxyURL;
    all_proxy = proxyURL;
    no_proxy = noProxy;
    HTTP_PROXY = proxyURL;
    HTTPS_PROXY = proxyURL;
    ALL_PROXY = proxyURL;
    NO_PROXY = noProxy;
  };
}
