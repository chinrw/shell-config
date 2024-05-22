# zsh-config

### Get submodules
git pull --recurse-submodules

### Install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

### Install Plugins
Replace current `.zshrc` and `.p10k.zsh`, `ln -s $PWD/zshrc ~/.zshrc` and `ln -s $PWD/p10k.zsh ~/.p10k.zsh`

### Install Plugins
```
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
git clone https://github.com/Pilaton/OhMyZsh-full-autoupdate.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ohmyzsh-full-autoupdate

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
