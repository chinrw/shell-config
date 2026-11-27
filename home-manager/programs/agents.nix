{ pkgs, ... }:
{
  imports = [
    ./agent-skills.nix
    ./agent-instructions/module.nix
    ./antigravity.nix
    ./claude-code
    ./codex
    ./dsh.nix
    ./pi
  ];

  home.packages = [
    pkgs.abtop
  ];
}
