{ ... }: {

  services.samba = {
    enable = true;
    openFirewall = true;
    # settings = {
    # };
    settings = {
      "global" = {
        "workgroup" = "WORKGROUP";
        "server string" = "chin39smb";
        "netbios name" = "chin39smb";
        "security" = "user";
        #use sendfile = yes
        "server min protocol" = "SMB2_10";
        "server max protocol" = "SMB3";
        #max protocol = smb2
        # note: localhost is the ipv6 localhost ::1
        "hosts allow" = "192.168.0., 127.0.0.1, 10.0.0., 10.10.0., localhost";
        "hosts deny" = "0.0.0.0/0";
        # guest account = nobody
        # map to guest = bad user
      };
      "mounts" = {
        path = "/home/chin39/mounts";
        browseable = "yes";
        writeable = "yes";
        public = "no";
        "valid users" = "chin39";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

}
