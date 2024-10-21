{ lib, pkgs, isDesktop, isWsl, noGUI, isWork, proxyUrl, ... }: {

  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Ruowen Qin";
        email = if (!isWork) then "chinqrw@gmail.com" else "ruqin@redhat.com";
      };
      ui.editor = "nvim";
    };
  };

  programs.git = {
    enable = true;
    aliases =
      {
        co = "checkout";
        lg = "lg1";
        lg1 = "lg1-specific --all";
        lg2 = "lg2-specific --all";
        lg3 = "lg3-specific --all";

        lg1-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)'";
        lg2-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)'";
        lg3-specific = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset) %C(bold cyan)(committed: %cD)%C(reset) %C(auto)%d%C(reset)%n''          %C(white)%s%C(reset)%n''          %C(dim white)- %an <%ae> %C(reset) %C(dim white)(committer: %cn <%ce>)%C(reset)'";

      };
    delta.enable = false;
    delta.options = {
      decorations = {
        commit-decoration-style = "bold yellow box ul";
        file-style = "bold yellow ul";
        file-decoration-style = "none";
        hunk-header-decoration-style = "yellow box";
      };

      unobtrusive-line-numbers = {
        line-numbers = true;
        line-numbers-minus-style = "#444444";
        line-numbers-zero-style = "#444444";
        line-numbers-plus-style = "#444444";
        line-numbers-left-format = "{nm:>4}┊";
        line-numbers-right-format = "{np:>4}│";
        line-numbers-left-style = "blue";
        line-numbers-right-style = "blue";
      };

      navigate = true; # use n and N to move between diff sections
      light = false; # set to true if you're in a terminal
      side-by-side = true;
      features = "unobtrusive-line-numbers decorations mantis-shrimp";
      whitespace-error-style = "22 reverse";
      true-color = "always";
    };
    difftastic.enable = true;


    userName = "Ruowen Qin";
    userEmail = if (!isWork) then "chinqrw@gmail.com" else "ruqin@redhat.com";

    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMasqR2edNuMaTk0djcs46/s/OiIQo97qa6oyF/ybgih";
      signByDefault = true;
    };
    extraConfig = {
      core = {
        packedGitLimit = "512m";
        packedGitWindowSize = "512m";
      };
      pack = {
        deltaCacheSize = "2047m";
        packSizeLimit = "2047m";
        windowMemory = "2047m";
      };


      gpg.format = "ssh";
      pull.rebase = true;
      push.autoSetupRemote = true;

      merge.conflictstyle = "zdiff3";
      init.defaultBranch = "main";
      interactive.diffFilter = "delta --color-only";
      http = {
        postBuffer = 524288000;
      } // lib.optionalAttrs (isWsl) {
        proxy = "http://127.0.0.1:10809";
      };
    };
  };
}
