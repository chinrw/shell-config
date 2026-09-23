{ pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    dataDir = "/var/lib/postgresql/17";
  };
}
