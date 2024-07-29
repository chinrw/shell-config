{ config, pkgs, ... }: {

  networking = {
    interfaces = {
      eth0.useDHCP = false;
      eth0.ipv4.addresses = [{
        address = "192.168.0.201";
        prefixLength = 24;
      }];
    };
    defaultGateway = {
      address = "192.168.0.1";
      interface = "eth0";
    };
  };

  networking.proxy.default = "http://192.168.0.201:10809";
  networking.enableIPv6 = false;

  # Enable WireGuard
  networking.wireguard.interfaces = {
    # "wg0" is the network interface name. You can name the interface arbitrarily.
    wg0 = {
      # Determines the IP address and subnet of the client's end of the tunnel interface.
      ips = [ "10.10.0.108/32" ];
      # listenPort = 51820; # to match firewall allowedUDPPorts (without this wg uses random port numbers)

      # Path to the private key file.
      #
      # Note: The private key can also be included inline via the privateKey option,
      # but this makes the private key world-readable; thus, using privateKeyFile is
      # recommended.
      privateKeyFile = config.sops.secrets."wg/privatekey".path;

      peers = [
        # For a client configuration, one peer entry for the server will suffice.

        {
          # Public key of the server (not a file path).
          publicKey = "iwyVuq0Q2FEqNYFjTKBEfW8buCpt+CpkUJBgwO9RLEs=";

          # Forward all the traffic via VPN.
          #allowedIPs = [ "0.0.0.0/0" ];
          # Or forward only particular subnets
          #allowedIPs = [ "10.100.0.1" "91.108.12.0/22" ];
          allowedIPs = [ " 10.0.0.0/24" "10.10.0.0/24" ];

          # Set this to the server IP and port.
          endpoint = "chin39.synology.me:7891";
          # ToDo: route to endpoint not automatically configured https://wiki.archlinux.org/index.php/WireGuard#Loop_routing
          # https://discourse.nixos.org/t/solved-minimal-firewall-setup-for-wireguard-client/7577

          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 15;
        }
      ];
    };
  };
}

