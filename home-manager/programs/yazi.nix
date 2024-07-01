{ config, ... }:
{
  home.file."${config.xdg.configHome}/yazi" = {
    source = ../../yazi;
    recursive = true;
  };
}
