{ config, pkgs, hostname, ... }: {

  wsl = {
    enable = true;
    defaultUser = "chin39";
    useWindowsDriver = true;
    wslConf.network.hostname = hostname;
  };

  networking = {
    interfaces = {
      eth0.useDHCP = false;
      eth0.ipv4.addresses = [{
        address = "10.0.0.202";
        prefixLength = 24;
      }];
    };
    defaultGateway = {
      address = "10.0.0.1";
      interface = "eth0";
    };
    nameservers = [ "10.0.0.1" ];
  };


  programs.proxychains = {
    package = pkgs.proxychains-ng;
    enable = true;
    quietMode = true;
    proxies = {
      local = {
        enable = true;
        type = "socks5";
        host = "10.0.0.201";
        port = 7891;
      };
    };
  };


  networking.proxy.default = "http://10.0.0.201:7891";
  networking.enableIPv6 = false;

  # Enable WireGuard
  # networking.wireguard.interfaces = {
  #   # "wg0" is the network interface name. You can name the interface arbitrarily.
  #   wg0 = {
  #     # Determines the IP address and subnet of the client's end of the tunnel interface.
  #     ips = [ "10.10.0.108/32" ];
  #     # listenPort = 51820; # to match firewall allowedUDPPorts (without this wg uses random port numbers)
  #
  #     # Path to the private key file.
  #     #
  #     # Note: The private key can also be included inline via the privateKey option,
  #     # but this makes the private key world-readable; thus, using privateKeyFile is
  #     # recommended.
  #     privateKeyFile = config.sops.secrets."wg/privatekey".path;
  #
  #     peers = [
  #       # For a client configuration, one peer entry for the server will suffice.
  #
  #       {
  #         name = "arch-synology";
  #
  #         # Public key of the server (not a file path).
  #         publicKey = "iwyVuq0Q2FEqNYFjTKBEfW8buCpt+CpkUJBgwO9RLEs=";
  #
  #         # Forward all the traffic via VPN.
  #         #allowedIPs = [ "0.0.0.0/0" ];
  #         # Or forward only particular subnets
  #         #allowedIPs = [ "10.100.0.1" "91.108.12.0/22" ];
  #         allowedIPs = [ " 10.0.0.0/24" "10.10.0.0/24" ];
  #
  #         # Set this to the server IP and port.
  #         endpoint = "chin39.synology.me:7891";
  #         # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing
  #         # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577
  #
  #         # Send keepalives every 25 seconds. Important to keep NAT tables alive.
  #         persistentKeepalive = 25;
  #
  #
  #         # Warning for endpoints with changing IPs:
  #         # The WireGuard kernel side cannot perform DNS resolution.
  #         # Thus DNS resolution is done once by the `wg` userspace
  #         # utility, when setting up WireGuard. Consequently, if the IP address
  #         # behind the name changes, WireGuard will not notice.
  #         # This is especially common for dynamic-DNS setups, but also applies to
  #         # any other DNS-based setup.
  #         # If you do not use IP endpoints, you likely want to set
  #         # {option}`networking.wireguard.dynamicEndpointRefreshSeconds`
  #         # to refresh the IPs periodically.
  #         dynamicEndpointRefreshSeconds = 60;
  #       }
  #     ];
  #   };
  # };
}
