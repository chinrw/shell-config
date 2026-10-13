# Notes for coding agents

This file is for agents changing this repository. Read `README.md` first. It
lists the hosts, the flake outputs and the deploy commands, and this file does
not repeat them.

## Committing

- Commit on local `main`. Do not open pull requests and do not push. The owner
  reviews and pushes batches. Fetch and rebase onto `origin/main` before
  committing, because the updater on nixos-ci pushes `flake.lock` updates to
  `main` every three hours.
- Commit as the repository's configured git user. Do not pass `--author`.
- Subjects use `<area>: <imperative description>`, where the area is the part
  of the tree that changed: `nixos`, `home-manager`, `deploy-rs`, `docs`, or a
  service name. Read `git log` for examples.
- Bodies are optional bullet lists of reasons the diff cannot show. Every
  commit ends with a `Signed-off-by:` line.

## Deploying a new target

The updater on nixos-ci builds `origin/main`, but it takes its list of build
targets from the configuration deployed on nixos-ci. Push a commit that adds a
host or an updater target before deploying it to nixos-ci. Otherwise the next
updater run fails because GitHub's copy does not have that output yet.

## Checking a change

- Run `nix fmt`.
- Build every output the change touches, for example
  `nix build .#nixosConfigurations.media-lxc.config.system.build.toplevel` or
  `nix build '.#homeConfigurations."chin39@vm-nix".activationPackage'`.
- For a change meant to be a pure refactor, compare `drvPath` before and after.
  A NixOS or nix-darwin toplevel changes on any commit because the registry
  embeds the flake's own source, so compare with the registry stripped.
- `nix run .#deploy-rs-ci -- --dry-activate .#<host>.system` shows what a
  deploy would change without activating it.

## Files that need the owner

- Do not edit `nixos/vm-nix/kernel.config`. Propose the `CONFIG_` change as a
  diff in your reply. Every change forces a full kernel rebuild, and the owner
  decides when that is worth it.
- Secrets live in `secrets/` and are sops-encrypted. Never write a plaintext
  secret into the tree.

## README

The README tells a reader how to use this repository: which hosts and outputs
exist, and how to build, deploy and maintain them. Do not describe how a
service is set up there, such as which services a host runs, their ports,
addresses, mounts or cache wiring. That detail lives in the Nix code, and a
copy in the README goes stale the next time a service moves. Give each host a
one-line role in the hosts table and nothing more.

## Code comments

Comments say why the code is the way it is: the constraint, the failure it
prevents, or the surprise. Scope caveats, history and pointers to other files
belong in the commit body, where they cannot go stale next to the code.

## Remote hosts

Login shells on the LAN hosts are zsh, which does not split an unquoted
`$VAR` into words. Pass multi-word commands as arrays or through `bash -s`
when running them over ssh.
