# boot with tmux
# if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
#   ctrl-alt-T
#   bindkey -M emacs '^[^T' renew_tmux_env
#   bindkey -M vicmd '^[^T' renew_tmux_env
#   bindkey -M viins '^[^T' renew_tmux_env
#   zle -N renew_tmux_env
#   tmux attach-session -t play || tmux new-session -s play
# fi


# Update Display variables with tmux
# if [ -n "$TMUX" ]; then
#     function renew_tmux_env_one {
#         oneenv=$(tmux show-environment | grep "^$1")
#         [[ ! -z $oneenv ]] && export $oneenv
#     }
#     function renew_tmux_env {
#         renew_tmux_env_one DISPLAY
#         renew_tmux_env_one SSH_CONNECTION
#         renew_tmux_env_one SSH_AUTH_SOCK
#         # update xauth
#         xauth merge $HOME/.Xauthority
#     }
# else
#     function renew_tmux_env {}
# fi
#
# function preexec {
#     renew_tmux_env
# }


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
ZSH_THEME="powerlevel10k/powerlevel10k"
# ZSH_THEME="spaceship-prompt/spaceship"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
HYPHEN_INSENSITIVE="true"
bindkey '\CI' expand-or-complete-prefix

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
# plugins=(git zsh-autosuggestions history-substring-search zsh-syntax-highlighting)


plugins=(fzf-tab git rust python pip sudo tmux systemd ohmyzsh-full-autoupdate ssh-agent cp brew archlinux docker docker-compose zsh-autosuggestions history-substring-search zsh-syntax-highlighting zoxide)
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
source $ZSH/oh-my-zsh.sh

# config zoxide
export _ZO_FZF_OPTS="--preview 'eza -G -a --color auto --sort=accessed --git --icons -s type {2}'"
# eval "$(zoxide init --cmd z zsh)"

# User configuration
zstyle ':fzf-tab:complete:eza:*' fzf-preview 'eza -G -a --color auto --sort=accessed --git --icons -s type $realpath'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -G -a --color auto --sort=accessed --git --icons -s type $realpath'
# disable sort when completing `git checkout`
zstyle ':completion:*:git-checkout:*' sort false
# set list-colors to enable filename colorizing
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# preview directory's content with eza when completing cd
zstyle ':fzf-tab:complete:systemctl-*:*' fzf-preview 'SYSTEMD_COLORS=1 systemctl status $word'

# it is an example. you can change it
zstyle ':fzf-tab:complete:git-(add|diff|restore):*' fzf-preview \
	'git diff $word | delta'
zstyle ':fzf-tab:complete:git-log:*' fzf-preview \
	'git log --color=always $word'
zstyle ':fzf-tab:complete:git-help:*' fzf-preview \
	'git help $word | bat -plman --color=always'
zstyle ':fzf-tab:complete:git-show:*' fzf-preview \
	'case "$group" in
	"commit tag") git show --color=always $word ;;
	*) git show --color=always $word | delta ;;
	esac'
zstyle ':fzf-tab:complete:git-checkout:*' fzf-preview \
	'case "$group" in
	"modified file") git diff $word | delta ;;
	"recent commit object name") git show --color=always $word | delta ;;
	*) git log --color=always $word ;;
	esac'

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

export EDITOR='nvim'

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
bindkey "^P" history-substring-search-up
bindkey "^N" history-substring-search-down

if [[ $TERM = dumb ]]; then
  unset zle_bracketed_paste
fi

PATH="$HOME/.local/bin:$PATH"
PATH="$HOME/.cargo/bin:$PATH"
PATH="$HOME/go/bin:$PATH"

TREE_IGNORE="cache|log|logs|node_modules|vendor"
if [ "$(command -v eza)" ]; then
    unalias -m 'll'
    unalias -m 'l'
    unalias -m 'la'
    alias ls='eza -G  --color auto --git --icons -s type'
    alias l='eza -G  --color auto --git --icons -s type'
    alias ll='eza -l -g --color always --git --icons -a -s type'
    alias lt='eza --color auto --icons -a -s type --tree -D -L 2 -I ${TREE_IGNORE}'
    alias ltt='eza --color auto --icons -a -s type --tree -D -L 3 -I ${TREE_IGNORE}'
fi

# eval "$(starship init zsh)"

# Add completion for 1passowrd 
if [ "$(command -v op)" ]; then
eval "$(op completion zsh)"; compdef _op op
fi

# zstyle ':autocomplete:*' min-input 1
# zstyle ':autocomplete:*' widget-style menu-select
# zstyle ':autocomplete:recent-dirs' backend zoxide
# zstyle ':autocomplete:*' recent-dirs zoxide
# zstyle ':autocomplete:*' fzf-completion yes
# source ~/config/zsh-autocomplete/zsh-autocomplete.plugin.zsh

# # bindkey '^P' up-line-or-search
# # Return key in completion menu & history menu
# bindkey -M menuselect '\r' accept-line

# use the vi navigation keys in menu completion
# bindkey -M menuselect 'h' vi-backward-char
# bindkey -M menuselect 'k' vi-up-line-or-history
# bindkey -M menuselect 'l' vi-forward-char
# bindkey -M menuselect 'j' vi-down-line-or-history

# enable history atuin
export ATUIN_NOBIND="true"
eval "$(atuin init zsh)"

bindkey '^r' _atuin_search_widget

# if [[ `uname` != "Darwin" ]]; then
#   precmd () {
#     echo -n -e "\a" >$TTY
#   }
# fi
bindkey \^U backward-kill-line

PATH="/home/chin39/perl5/bin${PATH:+:${PATH}}"; export PATH;
PERL5LIB="/home/chin39/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
PERL_LOCAL_LIB_ROOT="/home/chin39/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
PERL_MB_OPT="--install_base \"/home/chin39/perl5\""; export PERL_MB_OPT;
PERL_MM_OPT="INSTALL_BASE=/home/chin39/perl5"; export PERL_MM_OPT;

# Alias all flatpaks to their logical command names, but only if they're not already commands.
# tld.domain.AppName becomes the alias "appname"
# if "appname" is already used by another command then "tld.domain.AppName" is used instead.
# If both are used, nothing is aliased.

alias_flatpak_exports() {
  zmodload zsh/parameter
	local item
	for item in {${XDG_DATA_HOME:-$HOME/.local/share},/var/lib}/flatpak/exports/bin/*; do
		[ -x "$item" ] || continue

    local flatpak_short_alias="${item//*.}"
		local flatpak_long_alias="${item//*\/}"
	
		if [ ! "$(command -v "$flatpak_short_alias")" ]; then
      alias "${(L)flatpak_short_alias}"="$item"
		elif [ ! "$(command -v "$flatpak_long_alias")" ]; then
			alias "$flatpak_long_alias"="$item"
		fi
	done
}

if [ "$(command -v flatpak)" ] ; then
    PATH="/var/lib/flatpak/exports/bin:$PATH"
    PATH="$HOME/.local/share/flatpak/exports/bin:$PATH"
    alias_flatpak_exports
fi

if [ "${XDG_SESSION_TYPE}" = "wayland" -o "${XDG_SESSION_TYPE}" = "x11" ]
  then ln -f ${HOME}/.config/monitors.{${XDG_SESSION_TYPE},xml}
fi

# # 2x ctrl-d to exit ...
# export IGNOREEOF=1
#
# # bash like ctrl-d wrapper for IGNOREEOF
# setopt ignore_eof
# function bash-ctrl-d() {
#   if [[ $CURSOR == 0 && -z $BUFFER ]]
#   then
#     [[ -z $IGNOREEOF || $IGNOREEOF == 0 ]] && exit
#     if [[ "$LASTWIDGET" == "bash-ctrl-d" ]]
#     then
#       (( --__BASH_IGNORE_EOF <= 0 )) && exit
#     else
#       (( __BASH_IGNORE_EOF = IGNOREEOF ))
#     fi
#   fi
# }
# zle -N bash-ctrl-d
# bindkey "^d" bash-ctrl-d
