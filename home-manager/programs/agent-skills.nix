{ inputs, lib, ... }:
{
  imports = [ inputs.agent-skills.homeManagerModules.default ];

  programs.agent-skills.enable = true;

  # The existing shared-skill owner must finish before the new installer adopts links.
  home.activation.agentSkills = lib.hm.dag.entryAfter [ "claudeCodeAssets" ] (lib.mkDefault "");
}
