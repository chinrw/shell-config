{ ... }:
{
  # Shell history sync server for the hosts with the atuin-sync feature. The
  # client address is in home-manager/home.nix.
  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = 8881;
    # The owner registers from a client, so the server accepts registrations
    # instead of requiring `atuin-server admin user create` on the host.
    openRegistration = true;
    openFirewall = true;
  };
}
