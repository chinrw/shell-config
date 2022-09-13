
# install fish-like plugin
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# enable in plugins
plugins=(git pip brew zsh-autosuggestions history-substring-search zsh-syntax-highlighting)

# add this to .zshrc
bindkey "^P" history-substring-search-up
bindkey "^N" history-substring-search-down
