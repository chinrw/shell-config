# shell-config

One Nix flake for every machine I use: NixOS hosts, macOS through nix-darwin,
and plain Arch, Gentoo and Proxmox hosts that only run standalone home-manager.
System configuration and user dotfiles live in the same repo, and each host
deploys its own part.

| Path | What it is |
| --- | --- |
| `nixos/` | NixOS system modules. Per-host modules are under `nixos/<host>/` and services under `nixos/services/` |
| `darwin/` | nix-darwin system config for macOS |
| `home-manager/` | User environment. `home-manager/home.nix` is the entry point, and every host shares it |
| `overlays/`, `pkgs/`, `lib/` | Package overrides, custom packages and flake helpers. `lib/helpers.nix` builds the configurations, and `lib/caches.nix` lists the LAN caches |
| `secrets/` | sops-encrypted secrets |
| `shell/` | Dev shells: `nix develop .#hm`, `.#rust`, `.#kernel` (x86_64-linux only) |
| `yazi/`, `zellij/`, `wezterm/`, `tmux/` | App configs, symlinked into place by home-manager |

## Deploying

Every host runs home-manager standalone for the user configuration, so
`nixos-rebuild` and `darwin-rebuild` only manage the system side.
`darwin/default.nix` does not import the home-manager darwin module, because
the same dotfiles and launchd agents would otherwise be managed twice. A NixOS
or macOS host therefore takes two commands, and a plain Linux host takes only
the second one. The deploy-rs targets below keep the system and user
configurations separate in the same way.

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

### Plain Linux (Arch, Gentoo, Proxmox)

```sh
home-manager switch --flake .#chin39@archlinux
```

### Remote deployment with deploy-rs

deploy-rs deploys the NixOS configuration on `nixos-ci`, `nixos-lxc` and
`media-lxc`, and standalone Home Manager on `vm-nix`, `media-lxc` and
`proxmox`. Run it from an x86_64 Linux checkout, such as vm-nix. You need SSH
key access as `chin39`, trusted host keys, and passwordless sudo on the NixOS
targets.

The `nix run .#deploy-rs-ci` entry point sends builds for every target, including
its automatic checks, to `nixos-ci` (`192.168.0.230`). Cached outputs can still be
downloaded directly. It allows one remote build at a time with two cores and
disables local builds for those commands. If an uncached build needs CI while it
is unavailable, deployment fails before activation.

The local Nix daemon must be able to read your unencrypted
`$HOME/.ssh/id_ed25519`, and that key must authenticate as `chin39` on CI. The
builder's public host key is pinned in [pkgs/default.nix](pkgs/default.nix).
Leave deploy-rs's `--remote-build` option unset, because it makes the
deployment target the builder. Other Nix commands keep their usual build
settings. These settings take effect only after `nix run` has prepared the CLI
and its launcher.

| Target | Configuration |
| --- | --- |
| `nixos-ci.system` | `nixosConfigurations.nixos-ci` |
| `nixos-lxc.system` | `nixosConfigurations.nixos-lxc` |
| `media-lxc.system` | `nixosConfigurations.media-lxc` |
| `media-lxc.home` | `homeConfigurations."chin39@media-lxc"` |
| `vm-nix.home` | `homeConfigurations."chin39@vm-nix"` |
| `proxmox.home` | `homeConfigurations."chin39@proxmox"` |

Before the first activation, record the current generation and keep a console
recovery path available. The previous native generation lacks deploy-rs's
rollback script, so the first deployment may require manual recovery. Once a
known working deploy-rs generation is installed, later deployments can recover
to it automatically.

Check the configuration and preview the changes for the chosen target:

```sh
nix run .#deploy-rs-ci -- --dry-activate .#nixos-ci.system
```

Activate the chosen target with its explicit profile:

```sh
nix run .#deploy-rs-ci -- .#nixos-ci.system
nix run .#deploy-rs-ci -- .#nixos-lxc.system
nix run .#deploy-rs-ci -- .#vm-nix.home
```

Run one activation per target at a time, and coordinate with anyone else
working on that target. Once a host uses these profiles, activate it with
deploy-rs from then on. `nixos-rebuild switch` replaces the NixOS rollback
wrapper, and `home-manager switch` advances the native generation without
updating the deploy-rs wrapper. If you use either native command for recovery,
deploy once more with deploy-rs before relying on automatic rollback again.

deploy-rs confirms a deployment only by checking that SSH still connects, so
check the target's services yourself afterwards.

### Getting the `home-manager` CLI

`shell/home-manager.nix` provides a dev shell with the matching version:

```sh
nix develop .#hm
```

## Hosts

| System configuration | Machine |
| --- | --- |
| `nixosConfigurations.nixos-ci` | Proxmox LXC that refreshes `flake.lock` and prebuilds the cache (see below) |
| `nixosConfigurations.nixos-lxc` | Proxmox LXC for coding agents |
| `nixosConfigurations.media-lxc` | Proxmox LXC that runs the home services |
| `nixosConfigurations.vm-nix` | x86_64-linux server |
| `nixosConfigurations.wsl` | WSL2 with NVIDIA GPU |
| `nixosConfigurations.wsl-mini` | WSL2 with AMD GPU |
| `nixosConfigurations.work-laptop` | ThinkPad T14p Gen 2 with the niri desktop and the disk layout in `nixos/t14p-gen2/disko.nix` |
| `darwinConfigurations.macos` | Apple Silicon macOS |

All user configurations (`homeConfigurations`) share `home-manager/home.nix`,
and flags in `flake.nix` (`isServer`, `isPublic`, `noGUI`, `smallNode`,
`localCaches`) shape each one. Optional pieces such as restic, syncthing or
atuin sync are turned on per host through `features`. `lib/helpers.nix` lists
the valid feature names and rejects unknown ones. `proxy` and `gitProxy` set the
shell and git proxies.

The user configurations are:

`chin39@macos`, `chin39@desktop`, `chin39@vm-nix`, `chin39@wsl`,
`chin39@wsl-mini`, `chin39@work`, `chin39@vm-work`, `chin39@archlinux`,
`chin39@arch-lxc`, `chin39@arch-vm`, `chin39@proxmox`, `chin39@nixos-lxc`,
`chin39@media-lxc`, `chin39@gentoo-server`, `chin39@vm-gentoo`, `ruowen@ringo`

The ThinkPad pairs `nixosConfigurations.work-laptop` with
`homeConfigurations."chin39@work"`, and `nixos/services/shell-config-updater.nix`
prebuilds exactly those two outputs for it.

## Fresh install

`work-laptop` uses disko, and the disk in the config is a placeholder. Pass the
real device at install time (see `nixos/t14p-gen2/disko.nix`):

```sh
disko-install --flake .#work-laptop --disk main /dev/disk/by-id/nvme-...
```

Nothing reads the placeholder after installation, because every generated
mount goes through `/dev/disk/by-partlabel/*` or `/dev/mapper/cryptroot`.

## Secrets

Secrets are encrypted with sops and age. The age key lives at
`~/.config/sops/age/keys.txt` and must have no password, because hosts decrypt
it during activation with nobody there to type one
(`home-manager/programs/sops.nix`).

- The default file is `secrets/hosts.yaml`. Hosts flagged `isPublic` use
  `secrets/public/hosts.yaml` instead.
- `.sops.yaml` encrypts `secrets/*` to the `chin39` age key, and
  `secrets/server/*` to both the `server` and `chin39` keys.
- Edit a file with `sops secrets/hosts.yaml`. Files for a single service, such
  as `secrets/xray.conf` or `secrets/hermes.env`, are declared next to the
  service that reads them.

## Binary caches

`flake.nix` sets `extra-substituters` and `extra-trusted-public-keys`. It uses
the appending `extra-*` form because the replacing keys would overwrite the
settings in each host's `nix.conf`. Besides `chinrw.cachix.org` and a TUNA
mirror, a host can use LAN caches by naming them in `localCaches`. An unknown
name fails the build and prints the known ones, which are listed in
`lib/caches.nix`.

Every three hours `nixos-ci` runs `nixos/services/shell-config-updater.nix`. It
clones this repo, runs `nix flake update`, builds the configured Linux system
and home outputs, pushes them to Cachix, and only then pushes `main`. Other
machines therefore usually download prebuilt closures instead of building.

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

Do not symlink or edit these by hand. Do not rely on `~/.p10k.zsh` either,
because nothing on these hosts sources it. The p10k theme only sources its own
`internal/p10k.zsh`, and `~/.p10k.zsh` is just the path `p10k configure` writes
to.

The `zshrc` and `p10k.zsh` files at the repository root are a matched pair kept
for a machine with no Nix at all (see the legacy section below). They have
drifted from the home-manager copies, and editing them changes nothing on any
host in this flake. That includes the Arch, Gentoo and Proxmox hosts, which
already get zsh from standalone home-manager.

## Legacy manual setup (machines without Nix)

This section only applies to a host that runs neither NixOS, nix-darwin nor
home-manager. Link the two files into place. `zshrc` sources `~/.p10k.zsh`
itself.

```sh
ln -s $PWD/zshrc ~/.zshrc
ln -s $PWD/p10k.zsh ~/.p10k.zsh
```

### Get submodules

```sh
git pull --recurse-submodules
```

### Install oh-my-zsh

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### Install plugins

```sh
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
git clone https://github.com/Pilaton/OhMyZsh-full-autoupdate.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/ohmyzsh-full-autoupdate
```

### Rust terminal tools

```sh
cargo install exa atuin tealdeer du-dust fd-find ripgrep bat zoxide topgrade bandwhich
pacman -Sy exa atuin tealdeer dust fd ripgrep bat zoxide bandwhich
```

### Other plugins

- [zsh-completions](https://github.com/zsh-users/zsh-completions).
- [fzf-tab](https://github.com/Aloxaf/fzf-tab): clone it with
  `git clone https://github.com/Aloxaf/fzf-tab`, then add `fzf-tab` to the
  plugin list.
- [zsh-autocomplete](https://github.com/marlonrichert/zsh-autocomplete) is an
  alternative that this setup does not use.
