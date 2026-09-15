# LCM stores the default profile's history and summaries for later retrieval.
# Named profiles use Hermes' built-in compressor.
{
  pkgs,
  lib,
  inputs,
  user,
  group,
  summaryModel,
  summaryFallbackModels,
  summaryTimeoutSeconds,
}:
{
  # Inject only dependencies missing from the sealed Hermes environment.
  # The full FastEmbed closure collides with bundled packages.
  # Recheck this list when either dependency set changes.
  pythonPath = lib.makeSearchPath pkgs.python312.sitePackages (
    with pkgs.python312Packages;
    [
      fastembed
      onnxruntime
      tokenizers
      huggingface-hub
      numpy
      loguru
      mmh3
      py-rust-stemmers
      pystemmer
      snowballstemmer
      filelock
      fsspec
      hf-xet
      coloredlogs
      humanfriendly
    ]
  );

  # extraOptions is shell-joined; environment values must not contain spaces.
  containerEnvOptions = [
    "--env"
    "LCM_SUMMARY_MODEL=${summaryModel}"
    "--env"
    "LCM_SUMMARY_FALLBACK_MODELS=${lib.concatStringsSep "," summaryFallbackModels}"

    # Without this, one call may receive the whole non-tail backlog.
    "--env"
    "LCM_DYNAMIC_LEAF_CHUNK_ENABLED=true"

    # Do not inherit stale timeout state from mutable Profile config; tracks
    # auxiliary.compression.timeout.
    "--env"
    "LCM_SUMMARY_TIMEOUT_MS=${toString (summaryTimeoutSeconds * 1000)}"

    # lcm.db is a long-lived plaintext store of every raw message; redact
    # credential-shaped content (api_key/bearer/password/private-key
    # patterns) before storage, FTS indexing, and summarization.
    "--env"
    "LCM_SENSITIVE_PATTERNS_ENABLED=true"

    # Keep raw replay while making large tool results separately retrievable.
    "--env"
    "LCM_LARGE_OUTPUT_EXTERNALIZATION_ENABLED=true"

    # Sessions are mostly Chinese; an English summary layer would make
    # Chinese FTS over summaries miss. Injected into every summary call.
    "--env"
    "LCM_CUSTOM_INSTRUCTIONS=总结使用对话原语言（中文对话用中文写摘要）；逐字保留ID、路径、命令、URL、数值。"

    # Local multilingual embeddings support semantic recall.
    # Initialize with /lcm embed warmup, then review /lcm embed backfill --corpus both
    # before adding --apply; summary-only backfill omits raw-history vectors.
    "--env"
    "LCM_EMBEDDINGS_ENABLED=true"
    "--env"
    "LCM_EMBEDDING_PROVIDER=fastembed"
    "--env"
    "LCM_EMBEDDING_MODEL=sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

    # warmup/backfill (and status/doctor/backup) are slash-command-only;
    # destructive apply paths stay separately gated behind
    # LCM_DOCTOR_CLEAN_APPLY_ENABLED, which remains off.
    "--env"
    "LCM_ENABLE_SLASH_COMMAND=1"
  ];

  # Merged into services.hermes-agent.settings (default profile only).
  settings = {
    context.engine = "lcm";
    plugins.enabled = [ "hermes-lcm" ];
  };

  # Copy the plugin: container startup chowns this tree and cannot use a store symlink.
  # LCM databases live outside the replaced plugin directory.
  installScript = ''
    install -d -m 2770 \
      -o ${user} -g ${group} \
      "$hermes_home/plugins"
    rm -rf "$hermes_home/plugins/hermes-lcm"
    cp -r ${inputs.hermes-lcm} "$hermes_home/plugins/hermes-lcm"
    chown -R ${user}:${group} "$hermes_home/plugins/hermes-lcm"
    chmod -R u+rwX,g+rwX,o-rwx "$hermes_home/plugins/hermes-lcm"
  '';
}
