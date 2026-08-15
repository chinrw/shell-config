# hermes-lcm: Lossless Context Management engine for hermes default-profile
# sessions (the gateway's chat surfaces). Replaces the built-in
# rolling-summary compressor with a SQLite+DAG store — raw messages survive
# every compaction and lcm_* tools drill back into them, so long-lived
# sessions stop losing detail to repeated re-summarization.
#
# Scope and interplay (verified against hermes 0.20.0 + hermes-lcm v0.20.0):
#  - Plugins are allow-listed; media-mcp's portable plugin copy must stay
#    OFF plugins.enabled (mcp_servers registers those servers already).
#  - Specialist profiles keep the built-in compressor on purpose:
#    profileConfig does not repeat these keys, and profile clones predate
#    them. Kanban workers are short-lived; no DB churn.
#  - codex_responses_native stays true: LCM's trigger inherits the host
#    compression.threshold (0.50) + the codex autoraise, so native still
#    compacts gpt-5.6 server-side at 200K first. LCM keeps persisting raw
#    messages regardless, which also covers the issuer-sealed-blob loss on
#    a mid-session fallback to DeepSeek.
#  - LCM summarizes on auxiliary.compression's route with the model swapped
#    to flash (bare model ids override ONLY the model on that route —
#    escalation.py task="compression" + apply_lcm_model_route — so both
#    ride the Go gateway credential). auxiliary.compression itself stays on
#    Pro: compressor profiles need Pro's 1M window because the aux window
#    caps the compression trigger (conversation_compression.py:1597).
{
  pkgs,
  lib,
  inputs,
  user,
  group,
  deepseekFlash,
  deepseekPro,
}:
{
  # ── Local FastEmbed runtime for LCM semantic retrieval ────────────
  # LCM imports fastembed IN-PROCESS (embedding_provider.py:_load_fastembed),
  # so the package must be importable by the gateway's sealed venv python.
  # The module's extraPythonPackages option is unusable here: it walks the
  # full transitive closure onto PYTHONPATH and its build-time collision
  # checker hard-fails on the first overlap with the sealed venv (probed
  # 2026-08-15: "pillow collides"). Instead: inject ONLY the closure
  # members the venv lacks; the overlapping deps (requests, tqdm, pillow,
  # httpx, typing-extensions, packaging, pyyaml, urllib3, …) resolve from
  # the venv at import time since PYTHONPATH misses are fine.
  #
  # Maintenance contract: this is an explicit allowlist on purpose — if a
  # fastembed/nixpkgs bump grows a new transitive dep, imports fail LOUDLY
  # in the gateway instead of silently shadowing a venv package. Recompute
  # with: requiredPythonModules [ fastembed ] minus venv dist-info names.
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

  # Spliced into the container's extraOptions. NO SPACES inside any --env
  # value: extraOptions are joined unquoted into the docker create argv, so
  # whitespace splits the arg mid-value and docker dies on the leftovers
  # ("invalid reference format").
  containerEnvOptions = [
    # Flash primary: with dynamic chunking the summarizer sees bounded
    # 20K→40K chunks (≤12K out), far below the window that forced Pro for
    # the built-in compressor, and calls fire per leaf chunk + per
    # condensation, so flash's latency/quota edge compounds. Pro is an
    # AVAILABILITY fallback (error/circuit-breaker), not a quality one; the
    # terminal fallback is deterministic truncation.
    "--env"
    "LCM_SUMMARY_MODEL=${deepseekFlash}"
    "--env"
    "LCM_SUMMARY_FALLBACK_MODELS=${deepseekPro}"

    # Without this, one compaction pass summarizes the WHOLE non-tail
    # backlog in a single call (compaction.py: to_compact=candidate_raw) —
    # on a 1M DeepSeek session that is a several-hundred-K single-shot the
    # flash summarizer may not even fit, and failures only shrink 75%/50%
    # across 3 rescue retries before degrading to deterministic truncation.
    # Dynamic mode caps each leaf call at 20K→40K (base doubling to
    # LCM_DYNAMIC_LEAF_CHUNK_MAX) and drains the backlog across turns. The
    # flash-as-summarizer choice assumes these bounded calls.
    "--env"
    "LCM_DYNAMIC_LEAF_CHUNK_ENABLED=true"

    # Without an explicit value LCM derives its summary deadline from
    # config.yaml auxiliary.compression.timeout — a stale user key pins
    # that at 30s, which flash cannot honour on a 40K chunk at high effort
    # (timeouts burn the circuit breaker + spend guard, then degrade to
    # 512-token deterministic truncation).
    "--env"
    "LCM_SUMMARY_TIMEOUT_MS=120000"

    # lcm.db is a long-lived plaintext store of every raw message; redact
    # credential-shaped content (api_key/bearer/password/private-key
    # patterns) before storage, FTS indexing, and summarization.
    "--env"
    "LCM_SENSITIVE_PATTERNS_ENABLED=true"

    # Media tooling (LRR scans, qB lists) dumps huge JSON tool results;
    # externalize 12K+ char payloads to refs so summaries aren't drowned
    # and the DB stays lean. Active-replay stubbing and transcript GC stay
    # OFF — they rewrite what the model/store sees, opt in later.
    "--env"
    "LCM_LARGE_OUTPUT_EXTERNALIZATION_ENABLED=true"

    # Sessions are mostly Chinese; an English summary layer would make
    # Chinese FTS over summaries miss. Injected into every summary call.
    "--env"
    "LCM_CUSTOM_INSTRUCTIONS=总结使用对话原语言（中文对话用中文写摘要）；逐字保留ID、路径、命令、URL、数值。"

    # ── Semantic retrieval (local FastEmbed, CPU) ───────────────────
    # Fuzzy recall is the first-order gap: FTS-only scores R@5 0.20 /
    # turn-level 0.03 on the plugin's own LongMemEval run vs 0.87-0.96
    # for the vector arms, and CJK queries take a LIKE-substring fallback
    # on top. Multilingual model because the corpus is mixed zh/en
    # (Chinese chat + English code/logs); the benchmark's bge-small-en
    # is English-only. Model cache lands in ~/.cache/fastembed →
    # /home/hermes bind mount, persistent across container recreation.
    #
    # NOT self-activating: after deploy run, from a chat surface,
    #   /lcm embed warmup                          (downloads + registers dim)
    #   /lcm embed backfill --corpus both          (dry-run first)
    #   /lcm embed backfill --corpus both --apply
    # --corpus both is REQUIRED: the default backfill corpus is
    # "summary" only (command.py:3381), which would leave the raw-chunk
    # arm empty — and chunk vectors are the only vector arm codex-native
    # sessions (no DAG) ever get.
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

  # Spliced into the hermes-agent-profile-settings unit script, which
  # defines $hermes_home before this runs.
  #
  # A store symlink is NOT possible here: the OCI image's stage2 boot hook
  # chowns /data/.hermes recursively, dereferences the link into the
  # read-only store, and the container dies in a restart loop. Re-copy from
  # the pinned input on every start instead — content still comes only from
  # flake.lock, local edits are overwritten. lcm.db lives in .hermes/,
  # outside this tree. v0.20.0 ships no skills/ dir (the recall-policy
  # skill is v0.21-rc); revisit on bump.
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
