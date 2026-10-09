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
Linux hosts take only the second one. The deploy-rs targets below also keep
system and user configuration separate.

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

### Remote deployment with deploy-rs

deploy-rs deploys the NixOS configuration on `nixos-ci` and `nixos-lxc`, and
standalone Home Manager on `vm-nix`. Run it from an x86_64 Linux checkout, such
as vm-nix. You need SSH key access as `chin39`, trusted host keys, and passwordless
sudo on the two NixOS targets.

The `nix run .#deploy-rs-ci` entry point sends builds for all three targets, including
its automatic checks, to `nixos-ci` (`192.168.0.230`). Cached outputs can still be
downloaded directly. It allows one remote build at a time with two cores and
disables local builds for those commands. If an uncached build needs CI while it
is unavailable, deployment fails before activation.

The local Nix daemon must be able to read your unencrypted
`$HOME/.ssh/id_ed25519`, and that key must authenticate as `chin39` on CI. The
builder's public host key is pinned in [pkgs/default.nix](pkgs/default.nix).
Keep deploy-rs's `--remote-build` option unset because it selects the deployment
target as the builder. Other Nix commands retain their existing build settings.
This policy takes effect after `nix run` has prepared the CLI and its launcher.

| Target | Configuration |
| --- | --- |
| `nixos-ci.system` | `nixosConfigurations.nixos-ci` |
| `nixos-lxc.system` | `nixosConfigurations.nixos-lxc` |
| `vm-nix.home` | `homeConfigurations."chin39@vm-nix"` |

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

Run one activation per target at a time and coordinate with other users or chats
working on that target. After adopting these profiles, use deploy-rs for subsequent
NixOS and HM activations. `nixos-rebuild switch` replaces the NixOS rollback wrapper,
while `home-manager switch` advances the native HM generation without updating
the deploy-rs wrapper. After using either native command for recovery, establish
a matching deploy-rs baseline before relying on automatic rollback again.

SSH confirmation checks connectivity. Verify the target's services after each
deployment. The [validation record](docs/research/deploy-rs-validation.md) describes
the tested recovery paths and their limits.

### Getting the `home-manager` CLI

`shell/home-manager.nix` provides a dev shell with the matching version:

```sh
nix develop .#hm
```

## Hosts

| System configuration | Machine |
| --- | --- |
| `nixosConfigurations.nixos-ci` | Proxmox LXC that refreshes `flake.lock` and prebuilds the cache (see below) |
| `nixosConfigurations.nixos-lxc` | Proxmox LXC that runs the home services |
| `nixosConfigurations.vm-nix` | x86_64-linux server |
| `nixosConfigurations.wsl` | WSL2 with NVIDIA GPU |
| `nixosConfigurations.wsl-mini` | WSL2 with AMD GPU |
| `nixosConfigurations.work-laptop` | ThinkPad T14p Gen 2 — niri desktop, disk layout from `nixos/t14p-gen2/disko.nix` |
| `darwinConfigurations.macos` | Apple Silicon macOS |

User configurations (`homeConfigurations`) all share `home-manager/home.nix` and
are selected by flags in `flake.nix` (`isServer`, `isPublic`, `noGUI`,
`smallNode`, `localCaches`). Optional pieces such as restic, syncthing or atuin
sync are switched on per host through `features`. `lib/helpers.nix` lists the
valid names and rejects unknown ones. `proxy` and `gitProxy` set the shell and
git proxies.

The user configurations are:

`chin39@macos`, `chin39@desktop`, `chin39@vm-nix`, `chin39@wsl`,
`chin39@wsl-mini`, `chin39@work`, `chin39@vm-work`, `chin39@archlinux`,
`chin39@arch-lxc`, `chin39@arch-vm`, `chin39@proxmox`, `chin39@nixos-lxc`,
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

`nixos-ci` runs `nixos/services/shell-config-updater.nix` every three hours: it
clones this repo, runs `nix flake update`, builds the configured Linux system
and home outputs, pushes them to Cachix, and only then pushes `main`. So
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
