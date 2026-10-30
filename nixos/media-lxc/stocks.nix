{
  config,
  inputs,
  username,
  ...
}:

# The units come from the stocks repository's nix/module.nix; this file holds
# only what is specific to this host.
{
  imports = [ "${inputs.stocks}/nix/module.nix" ];

  # Read-only deploy key for the private repository; the updater fetches the
  # deploy/production branch with it.
  sops.secrets.stocks-deploy-key = {
    sopsFile = ../../secrets/stocks-deploy-key;
    format = "binary";
    owner = username;
    mode = "0400";
  };

  # CLAUDE_CODE_OAUTH_TOKEN from `claude setup-token`. It lasts a year and
  # does not refresh, unlike a /login session that would be stored in ~/.claude.
  sops.secrets.stocks-environment = {
    sopsFile = ../../secrets/stocks.env;
    format = "dotenv";
    key = "";
    mode = "0400";
    restartUnits = [ "stocks-server.service" ];
  };

  services.stocks = {
    enable = true;
    user = username;
    # web.nix serves this name through caddy.
    allowedOrigins = [ "https://stocks.home.midashood.top" ];
    deployKeyFile = config.sops.secrets.stocks-deploy-key.path;
    environmentFile = config.sops.secrets.stocks-environment.path;
    # claude and codex come from the user's Home Manager profile.
    path = [
      "/home/${username}/.nix-profile"
      "/run/current-system/sw"
    ];
    environment = {
      PROXY = config.networking.proxy.default;
      ANALYZER_ENGINE = "claude_cli";
      # Subscription mode blanks ANTHROPIC_API_KEY for the Claude CLI, which
      # would otherwise outrank CLAUDE_CODE_OAUTH_TOKEN.
      ANALYZER_CLI_USE_SUBSCRIPTION = "true";
      ANALYZER_CLI_MAX_TURNS = "30";
      ANALYZER_CLI_MAX_PARALLEL_AGENTS = "3";
    };
  };
}
