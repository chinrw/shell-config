{ inputs, ... }:
let
  port = 8888;
in
{
  imports = [ inputs.kikoeru-neo.nixosModules.default ];

  # The library stays in SQLite under /var/lib/kikoeru-neo. The two OpenList
  # libraries are added from the settings page, which keeps their password in
  # the data directory, so this config holds no secret and no roots.
  services.kikoeru-neo = {
    enable = true;
    settings = {
      # Every address, so the LAN can also use plain HTTP on :8888.
      listen = "0.0.0.0:${toString port}";
      # caddy in web.nix serves HTTPS on this name and proxies from loopback.
      public_url = "https://kikoeru.home.midashood.top";
      trusted_proxies = [ "127.0.0.1" ];
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
