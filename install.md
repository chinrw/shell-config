### Install zoxide fzf
```
pacman -Sy zoxide fzf
```


### Install powerlevel10k
```
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```
- Set `ZSH_THEME="powerlevel10k/powerlevel10k"` in `~/.zshrc`

### Enable in plugins in .zshrc
> plugins=(git pip brew zsh-autosuggestions history-substring-search zsh-syntax-highlighting)


### Install fish-like plugin
```
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### Enable in plugins in .zshrc
`plugins=(git pip brew zsh-autosuggestions history-substring-search zsh-syntax-highlighting)`

Note: make sure zsh-syntax-highlighting is the last one in the above list.

### Add this to .zshrc
```
ZSH_AUTOSUGGEST_STRATEGY=(completion history)
bindkey "^P" history-substring-search-up
bindkey "^N" history-substring-search-down
eval "$(zoxide init --cmd cd zsh)"
```
