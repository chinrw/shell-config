{ config, pkgs, ... }: {

  services.github-runners = {
    runner1 = {
      enable = true;
      name = "midashood";
      tokenFile = config.sops.secrets."github-runners/midashood".path;
      url = "https://github.com/rex-rs/rex";
      extraLabels = [ "nix" ];
    };
  };
}
