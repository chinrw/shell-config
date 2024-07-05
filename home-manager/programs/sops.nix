{ config, ... }:
{
  sops = {
    age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";
    secrets = {
      "proxy/work" = {
        # sopsFile = ./secrets.yml.enc; # optionally define per-secret files

        # %r gets replaced with a runtime directory, use %% to specify a '%'
        # sign. Runtime dir is $XDG_RUNTIME_DIR on linux and $(getconf
        # DARWIN_USER_TEMP_DIR) on darwin.
        # path = "%r/test.txt";
      };
      "proxy/clash" = { };
    };
  };
}
