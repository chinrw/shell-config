# zsh-config


### Installed Plugins
```
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting


```
#### rust terminal tools
cargo install exa atuin tealdeer du-dust fd-find ripgrep bat zoxide topgrade bandwhich

pacman -Sy exa atuin tealdeer dust fd ripgrep bat zoxide bandwhich

#### Install zsh-autocomplete (not using)
https://github.com/marlonrichert/zsh-autocomplete

#### Install zsh-completions
https://github.com/zsh-users/zsh-completions

#### Install fzf-tab with omz
`git clone https://github.com/Aloxaf/fzf-tab`

add `fzf-tab` to plugin
