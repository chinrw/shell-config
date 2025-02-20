{ hostname, ... }: {
  wsl = {
    enable = true;
    defaultUser = "chin39";
    useWindowsDriver = true;
    wslConf.network = {
      # let linux handle hosts
      generateHosts = false;
      hostname = hostname;
    };
  };
}
