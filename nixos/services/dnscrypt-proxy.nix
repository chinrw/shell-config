{ ... }:
{
  services.dnscrypt-proxy = {
    enable = true;
    settings = {
      server_names = [ "cloudflare" ];
      proxy = "socks5://127.0.0.1:10808";
      cache = true;
      sources = { };
      static.cloudflare.stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
    };
  };
}
