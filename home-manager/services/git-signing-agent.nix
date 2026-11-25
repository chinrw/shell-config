{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtimeDirectory = "git-signing-agent";
  socket = "${runtimeDirectory}/agent.sock";
  privateKey = "${config.home.homeDirectory}/.ssh/id_ed25519";
  signingKey = lib.removePrefix "key::" config.programs.git.signing.key;
  sshKeygen = lib.getExe' pkgs.openssh "ssh-keygen";
in
{
  # Git selects this socket even when the SSH client has not forwarded an
  # agent or the remote worker did not inherit the shell environment.
  programs.git.signing.signer = toString (
    pkgs.writeShellScript "git-ssh-keygen" ''
      if [[ "''${1-}" == -Y && "''${2-}" == sign ]]; then
        export SSH_AUTH_SOCK="/run/user/$(${lib.getExe' pkgs.coreutils "id"} -u)/${socket}"
      fi
      exec ${sshKeygen} "$@"
    ''
  );

  systemd.user.services.git-signing-agent = {
    Unit.Description = "SSH agent for Git commit and tag signing";
    Service = {
      # ssh-agent binds the socket before its parent exits.
      Type = "forking";
      RuntimeDirectory = runtimeDirectory;
      RuntimeDirectoryMode = "0700";
      StandardOutput = "null";
      Environment = [
        "SSH_AUTH_SOCK=%t/${socket}"
        "SSH_ASKPASS_REQUIRE=never"
      ];
      ExecStartPre = toString (
        pkgs.writeShellScript "check-git-signing-key" ''
          key_file=${lib.escapeShellArg privateKey}
          public_key=$(${sshKeygen} -y -P "" -f "$key_file" < /dev/null) || exit 1
          read -r key_type key_blob _ <<< "$public_key"
          if [[ "$key_type $key_blob" != ${lib.escapeShellArg signingKey} ]]; then
            echo "The private key at $key_file does not match Git's signing key" >&2
            exit 1
          fi
        ''
      );
      ExecStart = "${lib.getExe' pkgs.openssh "ssh-agent"} -a %t/${socket}";
      ExecStartPost = ''${lib.getExe' pkgs.openssh "ssh-add"} -q -k "${privateKey}"'';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
