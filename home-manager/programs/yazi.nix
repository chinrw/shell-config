{ config, ... }:
{
  file."${config.xdg.configHome}/yazi" = {
    source = ../zellij;
    recursive = true;
  };
}
