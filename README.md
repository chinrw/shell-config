# shell-config

One Nix flake for every machine I use: NixOS hosts, macOS via nix-darwin, and
plain Arch / Gentoo / Proxmox hosts that only run **standalone home-manager**.
System configuration and user dotfiles live in the same repo and are deployed
per host.

| Path | What it is |
| --- | --- |
| `nixos/` | NixOS system modules; per-host modules under `nixos/<host>/`, services under `nixos/services/` |
| `darwin/` | nix-darwin system config for macOS |
| `home-manager/` | User environment; `home-manager/home.nix` is the entry point and is shared by **every** host |
| `overlays/`, `pkgs/`, `lib/` | Package overrides, custom packages, flake helpers (`lib/helpers.nix` builds the configurations, `lib/caches.nix` is the LAN cache registry) |
| `secrets/` | sops-encrypted secrets |
| `shell/` | Dev shells: `nix develop .#hm`, `.#rust`, `.#kernel` (x86_64-linux only) |
| `yazi/`, `zellij/`, `wezterm/`, `tmux/` | App configs, symlinked into place by home-manager |

## Deploying

User config is standalone home-manager on **every** host — `nixos-rebuild` and
`darwin-rebuild` manage the system side only (`darwin/default.nix` deliberately
does not import the home-manager darwin module, or the same dotfiles and launchd
agents would be managed twice). System hosts therefore take two commands; plain
Linux hosts take only the second one.

### NixOS hosts

```sh
sudo nixos-rebuild switch --flake .#vm-nix      # or wsl, wsl-mini, work-laptop
home-manager switch      --flake .#chin39@vm-nix
```

### macOS

```sh
darwin-rebuild switch --flake .#macos
home-manager   switch --flake .#chin39@macos
```

### Plain Linux (Arch / Gentoo / Proxmox) — standalone home-manager only

```sh
home-manager switch --flake .#chin39@archlinux
```

### Getting the `home-manager` CLI

`shell/home-manager.nix` provides a dev shell with the matching version:

```sh
nix develop .#hm
```

## Hosts

| System configuration | Machine |
| --- | --- |
| `nixosConfigurations.vm-nix` | x86_64-linux server; also the host that refreshes `flake.lock` and prebuilds the cache (see below) |
| `nixosConfigurations.wsl` | WSL2 with NVIDIA GPU (`GPU = "nvidia"`) |
| `nixosConfigurations.wsl-mini` | WSL2 with AMD GPU (`GPU = "amd"`) |
| `nixosConfigurations.work-laptop` | ThinkPad T14p Gen 2 — niri desktop, disk layout from `nixos/t14p-gen2/disko.nix` |
| `darwinConfigurations.macos` | Apple Silicon macOS |

User configurations (`homeConfigurations`) all share `home-manager/home.nix` and
are selected by flags in `flake.nix` (`isServer`, `isPublic`, `noGUI`,
`smallNode`, `localCaches`):

`chin39@macos`, `chin39@desktop`, `chin39@vm-nix`, `chin39@wsl`,
`chin39@wsl-mini`, `chin39@work`, `chin39@vm-work`, `chin39@archlinux`,
`chin39@arch-lxc`, `chin39@arch-vm`, `chin39@proxmox`, `chin39@jd-cloud`,
`chin39@gentoo-server`, `chin39@vm-gentoo`, `ruowen@ringo`

The ThinkPad pairs `nixosConfigurations.work-laptop` with
`homeConfigurations."chin39@work"`; `nixos/services/shell-config-updater.nix`
builds exactly those two outputs for it.

## Fresh install

`work-laptop` uses disko, and the disk in the config is a placeholder. Pass the
real device at install time (see `nixos/t14p-gen2/disko.nix`):

```sh
disko-install --flake .#work-laptop --disk main /dev/disk/by-id/nvme-...
```

Nothing reads that placeholder afterwards: every generated mount goes through
`/dev/disk/by-partlabel/*` or `/dev/mapper/cryptroot`.

## Secrets

sops + age. The age key lives at `~/.config/sops/age/keys.txt` and must have no
password (`home-manager/programs/sops.nix`).

- Default file: `secrets/hosts.yaml`. Hosts flagged `isPublic` use
  `secrets/public/hosts.yaml` instead.
- `.sops.yaml` gives `secrets/*` to the `chin39` age key, and `secrets/server/*`
  to both the `server` and `chin39` keys.
- Edit with `sops secrets/hosts.yaml`. Service-specific files (`secrets/xray.conf`,
  `secrets/hermes.env`, …) are declared next to the service that consumes them.

## Binary caches

`flake.nix` sets `extra-substituters` / `extra-trusted-public-keys` (the
appending `extra-*` form on purpose — the replacing keys would clobber each
host's `nix.conf`). Besides `chinrw.cachix.org` and a TUNA mirror, each host can
opt into LAN caches by naming them in `localCaches`; unknown names fail the
build with the list of known ones (`lib/caches.nix`, resolved in
`lib/helpers.nix`).

`vm-nix` runs `nixos/services/shell-config-updater.nix` every three hours: it
clones this repo, runs `nix flake update`, builds the `vm-nix` and `work-laptop`
system + home outputs, pushes them to Cachix, and only then pushes `main`. So
other machines normally pull prebuilt closures instead of building.

## Everyday commands

```sh
nix fmt                        # nixfmt-tree, the flake's formatter
nix develop .#rust             # Rust dev shell
nix run .#check-xray-version   # is the pinned xray override in overlays/ still needed?
git submodule update --init --recursive   # tmux, qemu-script, yazi plugins
```

## zsh / powerlevel10k configuration

The live shell config is generated from `home-manager/programs/zsh/` on every
host:

- `~/.config/zsh/.zshrc` (`programs.zsh.dotDir` moves zsh's dot dir here, so a
  hand-written `~/.zshrc` is never read)
- `~/.config/zsh/plugins/powerlevel10k-config/p10k.zsh`

Do **not** symlink or edit these by hand, and do not rely on `~/.p10k.zsh` — it
is not sourced on these hosts (the p10k theme only sources its own
`internal/p10k.zsh`; `~/.p10k.zsh` is only the path `p10k configure` would
*write* to).

The `zshrc` and `p10k.zsh` files at the repository root are a matched pair kept
only for a machine with no Nix at all (see the legacy section below). They have
drifted from the home-manager copies, so **edits to them have no effect** on any
host in this flake — including the Arch / Gentoo / Proxmox hosts, which already
get zsh from standalone home-manager.

## Legacy manual setup (machines without Nix)

Only relevant for a host that does not run NixOS, nix-darwin or home-manager.
`ln -s $PWD/zshrc ~/.zshrc` and `ln -s $PWD/p10k.zsh ~/.p10k.zsh` (`zshrc`
itself sources `~/.p10k.zsh`).

### Get submodules
git pull --recurse-submodules

### Install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

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
