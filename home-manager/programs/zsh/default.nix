{
  lib,
  pkgs,
  isDesktop,
  noGUI,
  proxyUrl,
  config,
  ...
}:
{

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    localVariables = {
      # variable for eza
      TREE_IGNORE = [ "cache|log|logs|node_modules|vendor" ];
    };

    initContent = lib.mkMerge [
      (lib.mkBefore "
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r \"\${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh\" ]]; then
  source \"\${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-\${(%):-%n}.zsh\"
fi
")
      (lib.mkOrder 850 "
# Load fzf after Oh My Zsh (order 800), but before fzf-tab (order 900),
# so fzf-tab remains the owner of Tab completion.
if [[ $options[zle] = on ]]; then
  source <(${lib.getExe pkgs.fzf} --zsh)
fi
")
      (
        lib.optionalString (proxyUrl != "")
          "
_proxy_url=$(<\"${proxyUrl}\")
export http_proxy=\"$_proxy_url\"
export https_proxy=\"$_proxy_url\"
unset _proxy_url
"
        + "

# User configuration
zstyle ':fzf-tab:complete:eza:*' fzf-preview 'eza -G -a --color auto --sort=accessed --git --icons -s type $realpath'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -G -a --color auto --sort=accessed --git --icons -s type $realpath'
# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors \${(s.:.)LS_COLORS}
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'

# it is a fzf example. you can change it
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview \\
	'git diff $word | delta'
zstyle ':fzf-tab:complete:git-log:*' fzf-preview \\
	'git log --color=always $word'
zstyle ':fzf-tab:complete:git-help:*' fzf-preview \\
	'git help $word | bat -plman --color=always'
zstyle ':fzf-tab:complete:git-show:*' fzf-preview \\
	'case \"\$group\" in
	\"commit tag\") git show --color=always $word ;;
	*) git show --color=always $word | delta ;;
	esac'
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview \\
	'case \"\$group\" in
	\"modified file\") git diff $word | delta ;;
	\"recent commit object nam\") git show --color=always $word | delta ;;
	*) git log --color=always $word ;;
	esac'

bindkey \"^P\" history-substring-search-up
bindkey \"^N\" history-substring-search-down

_dstask() {
    compadd -- $(dstask _completions \"\${words[@]}\")
}

compdef _dstask dstask

if [[ $TERM = dumb ]]; then
  unset zle_bracketed_paste
fi

bindkey \^U backward-kill-line
bindkey '^r' _atuin_search_widget

# Run hermes against the rootful docker socket where hermes-agent
# actually lives. chin39's default DOCKER_HOST points at rootless
# (via virtualisation.docker.rootless.setSocketVariable), but the
# hermes-agent container runs under the rootful daemon (systemd
# service runs as root). chin39 is in the docker group, so
# /var/run/docker.sock is directly accessible -- no sudo needed.
hermes() {
  DOCKER_HOST=unix:///var/run/docker.sock command hermes \"\$@\"
}

"
        + lib.optionalString pkgs.stdenv.isDarwin "
# Fix Time Machine 'backup failed' on the NAS SMB destination. backupd
# can only enable TM network volume options on an SMB mount it creates
# itself; a lingering mount (eject blocked after a successful backup,
# or the share mounted manually) makes every backup fail with fsctl
# error 45 'does not support required network capabilities'. Clear the
# stale sparsebundle + mountpoint, then start a fresh backup.
tmfix() {
  if tmutil status | grep -q 'Running = 1'; then
    echo 'tmfix: a backup is running; not touching anything' >&2
    return 1
  fi
  local dev mp found=0
  dev=\$(hdiutil info | awk '/sparsebundle/{f=1;next} f && \$1 ~ \"^/dev/disk\" {print \$1; exit}')
  if [[ -n \$dev ]]; then
    found=1
    echo \"tmfix: detaching sparsebundle \$dev\"
    hdiutil detach \"\$dev\" || return 1
  fi
  for mp in /Volumes/.timemachine/*/*/timemachine(N) /Volumes/timemachine(N); do
    found=1
    echo \"tmfix: unmounting \$mp\"
    diskutil unmount \"\$mp\" || return 1
  done
  if (( found )); then
    tmutil startbackup
  else
    echo 'tmfix: no stale Time Machine mounts found'
  fi
}

"
        + lib.optionalString isDesktop "
alias_flatpak_exports() {
  zmodload zsh/parameter
	local item
	for item in {\${XDG_DATA_HOME:-$HOME/.local/share},/var/lib}/flatpak/exports/bin/*; do
		[ -x \"$item\" ] || continue

    local flatpak_short_alias=\"\${item//*.}\"
		local flatpak_long_alias=\"\${item//*\/}\"
	
		if [ ! \"$(command -v \"$flatpak_short_alias\")\" ]; then
      alias \"\${(L)flatpak_short_alias}\"=\"$item\"
		elif [ ! \"\$(command -v \"\$flatpak_long_alias\")\" ]; then
			alias \"$flatpak_long_alias\"=\"$item\"
		fi
	done
}

if [ \"$(command -v flatpak)\" ] ; then
    PATH=\"/var/lib/flatpak/exports/bin:$PATH\"
    PATH=\"$HOME/.local/share/flatpak/exports/bin:$PATH\"
    alias_flatpak_exports
fi
"
      )
    ];

    profileExtra = ''
      # Source Nix profile for single user mode
      if [ -e /home/chin39/.nix-profile/etc/profile.d/nix.sh ]; then
        . /home/chin39/.nix-profile/etc/profile.d/nix.sh
      fi
      # Re-exec into Nix's zsh to avoid glibc mismatch with Nix-built modules.
      # The exported sentinel caps this at one exec per session lineage: the
      # /proc-based check alone can stay true forever when /proc is absent
      # (Darwin) or $$/exe resolves through a wrapper, which would exec-loop.
      if [[ -z "$_NIX_ZSH_REEXECED" && ! "$(readlink /proc/$$/exe 2>/dev/null)" == /nix/store/* ]]; then
        _nix_zsh="$(command -v zsh 2>/dev/null)"
        if [[ "$_nix_zsh" == /nix/store/* ]]; then
          export _NIX_ZSH_REEXECED=1
          exec "$_nix_zsh" -l
        fi
        unset _nix_zsh
      fi
    ''
    + lib.optionalString pkgs.stdenv.isDarwin ''
      # Homebrew shellenv on macOS — nix-darwin manages the brew manifest
      # but does not put /opt/homebrew/bin (Apple Silicon) or
      # /usr/local/bin (Intel) on PATH for us.
      if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    '';

    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      # {
      #   name = "zsh-syntax-highlighting";
      #   src = pkgs.zsh-syntax-highlighting;
      #   file = "share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh";
      # }
      # {
      #   name = "zsh-autosuggestions";
      #   src = pkgs.zsh-autosuggestions;
      #   file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      # }
      {
        name = "zsh-nix-shell";
        src = pkgs.zsh-nix-shell;
        file = "share/zsh-nix-shell/nix-shell.plugin.zsh";
      }
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.zsh";
      }
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = lib.cleanSource ./p10k-config;
        file = "p10k.zsh";
      }
      {
        name = "rclone_complete";
        src = pkgs.rclone;
        file = "share/zsh/site-functions/_rclone";
      }
    ];

    shellAliases = {
      ls = "eza -G  --color auto --git --icons -s type";
      l = "eza -G  --color auto --git --icons -s type";
      ll = "eza -l -g --color always --git --icons -a -s type";
      lt = "eza --color auto --icons -a -s type --tree -D -L 2 -I \${TREE_IGNORE}";
      ltt = "eza --color auto --icons -a -s type --tree -D -L 3 -I \${TREE_IGNORE}";
      ds = "dstask";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [
        "1password"
        "git"
        "jj"
        "python"
        "pip"
        "systemd"
        "ssh-agent"
        "docker"
        "docker-compose"
        "history-substring-search"
      ];
      extraConfig = ''
        # Must be set before Oh My Zsh initializes completion.
        HYPHEN_INSENSITIVE="true"
      '';
    };

  };
}
