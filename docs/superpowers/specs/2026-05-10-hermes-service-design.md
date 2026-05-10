# Hermes Agent as a NixOS service on `vm-nix`

**Status:** design approved, implementation pending
**Date:** 2026-05-10
**Author:** chin39 + Claude (brainstorming session)
**Target host:** `vm-nix` (192.168.0.240, x86_64-linux, AMD)
**Reference:** https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup

## 1. Goal & Non-goals

**Goal.** Run Hermes Agent as a managed, declarative NixOS service on `vm-nix`, with the local llama.cpp server at `192.168.0.101:8087` as the default model and DeepSeek (`deepseek-v4-flash`) wired in as the auxiliary compression model and a one-command CLI swap. Secrets via sops-nix following the existing `secrets/hosts.yaml` pattern. No container — native hardened systemd.

**Non-goals (for v1).**
- No MCP servers wired (scaffold-only; add later as separate sprints)
- No edits to `nixos/services/llm.nix` — the existing `open-webui` service on `wsl` is unrelated
- No GPU passthrough — `vm-nix` is AMD and the model server is on a separate machine
- No automatic provider-failover routing (hermes doesn't do this; user picks via `/model` slash-command or `--model` flag)

## 2. Architecture

```
┌────────────────────────────── vm-nix host (192.168.0.240) ────────────────────────────────┐
│                                                                                            │
│  /home/chin39/shell-config/                                                                │
│  ├─ nixos/services/hermes.nix         ← new module                                         │
│  ├─ nixos/vm-nix/default.nix          ← edited: one line in imports                        │
│  ├─ secrets/hermes.env                ← new sops file (dotenv, encrypted to chin39)        │
│  ├─ flake.nix                         ← edited: hermes-agent input added                   │
│  └─ flake.lock                        ← regenerated                                        │
│                                                                                            │
│  At activation: sops-nix (running as root, using                                           │
│  /home/chin39/.config/sops/age/keys.txt) decrypts secrets/hermes.env →                     │
│  /run/secrets/hermes-env  (mode 0400, owner hermes)                                        │
│                                                                                            │
│  ┌────────────────────────────────────────────────────────────────────────┐                │
│  │  systemd: hermes-agent.service  (managed mode, hardened)               │                │
│  │  ├─ user/group:    hermes:hermes  (system user, no shell)              │                │
│  │  ├─ stateDir:      /var/lib/hermes/                                    │                │
│  │  │                  ├─ .hermes/  (HERMES_HOME)                         │                │
│  │  │                  │   ├─ config.yaml  ← rendered from `settings`     │                │
│  │  │                  │   └─ .env         ← merged from environmentFiles │                │
│  │  │                  ├─ workspace/       ← MESSAGING_CWD                │                │
│  │  │                  └─ .gc-root         ← keeps package alive          │                │
│  │  ├─ sandbox:       NoNewPrivileges, ProtectSystem=strict, PrivateTmp,  │                │
│  │  │                 ReadWritePaths=[stateDir]                           │                │
│  │  ├─ tools on PATH: hermes' sealed venv (python3.12 + uv) +             │                │
│  │  │                 everything in `extraPackages` (see §4)              │                │
│  │  ├─ ExecStartPre:  probe llama.cpp /v1/models, write LOCAL_MODEL_NAME  │                │
│  │  │                 to /run/hermes/discovered.env                       │                │
│  │  └─ entrypoint:    hermes gateway run --replace                        │                │
│  └────────────────────────────────────────────────────────────────────────┘                │
│                                                                                            │
│  Host CLI:  /run/current-system/sw/bin/hermes  (talks to gateway via local socket)         │
│                                                                                            │
└────────────────────────┬─────────────────────────┬─────────────────────────────────────────┘
                         │                         │
                         │ HTTP (LAN, no proxy)    │ HTTPS via 192.168.0.240:10809
                         ▼                         ▼
                192.168.0.101:8087         api.deepseek.com/v1
                llama.cpp (default)        DeepSeek (compression + `/model deepseek` swap)
```

### Boundary choices

- **Native systemd, not container.** Matches the rest of the flake's "everything declarative" posture. Sandbox is `NoNewPrivileges` + `ProtectSystem=strict` + `PrivateTmp` (applied automatically by the hermes module). Host filesystem is read-only to hermes except `${stateDir}`.
- **Sops via chin39's user age key** (existing pattern from `aria2.nix` and `github-runners.nix`). No host age key bootstrap needed — sops-nix runs as root at activation, reads `/home/chin39/.config/sops/age/keys.txt`, writes decrypted output to `/run/secrets/hermes-env` owned by `hermes`.
- **No docker dependency for hermes itself.** The existing rootful + rootless docker on `vm-nix` (used by jellyfin, etc.) remains untouched.
- **Outbound to DeepSeek** uses the existing `networking.proxy.default = "http://192.168.0.240:10809"`. LAN traffic to `192.168.0.101` is in `proxy.noProxy` (`192.168.0.0/24`) and goes direct.

## 3. Files

| Path | Status | Lines |
|---|---|---|
| `flake.nix` | edited | +5 |
| `nixos/vm-nix/default.nix` | edited | +1 |
| `nixos/services/hermes.nix` | new | ~110 |
| `secrets/hermes.env` | new (sops-encrypted) | n/a |
| `flake.lock` | regenerated | mechanical |

### `flake.nix` (edit)

Add input:

```nix
inputs = {
  # …existing inputs…
  hermes-agent = {
    url = "github:NousResearch/hermes-agent";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

No changes to `nixosConfigurations`; the module attaches itself when `hermes.nix` is in the imports chain.

### `nixos/vm-nix/default.nix` (edit)

One line in the existing `imports` list:

```nix
imports = [
  inputs.hardware.nixosModules.common-cpu-amd
  ./hardware.nix
  ./wireguard.nix
  # …existing imports…
  ../services/hermes.nix          # ← new
];
```

The existing `sops` block (lines 142–156) carries forward; `hermes.nix` extends `sops.secrets` via NixOS module merging.

### `nixos/services/hermes.nix` (new)

Skeleton; final form rendered during implementation (see §5 for the exact `settings` block):

```nix
{ config, lib, pkgs, inputs, ... }:
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  sops.secrets."hermes-env" = {
    sopsFile = ../../secrets/hermes.env;
    format   = "dotenv";
    owner    = "hermes";
    mode     = "0400";
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [
      config.sops.secrets."hermes-env".path
      "/run/hermes/discovered.env"           # written by ExecStartPre
    ];
    settings = { /* see §5 */ };
    extraPackages = with pkgs; [ /* see §4 */ ];
    extraPythonPackages = ps: with ps; [ /* see §4 */ ];
    restart    = "always";
    restartSec = 5;
  };

  systemd.services.hermes-agent = {
    serviceConfig.RuntimeDirectory     = "hermes";
    serviceConfig.RuntimeDirectoryMode = "0750";
    serviceConfig.ExecStartPre = lib.mkAfter [
      (pkgs.writeShellScript "hermes-probe-local-model" ''
        set -uo pipefail
        OUT=/run/hermes/discovered.env
        MODEL=$(${pkgs.curl}/bin/curl -fsS --max-time 5 \
          http://192.168.0.101:8087/v1/models 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.data[0].id // empty' 2>/dev/null \
          || true)
        if [ -z "$MODEL" ]; then
          MODEL="local-unavailable"
          echo "[hermes-probe] llama.cpp unreachable; LOCAL_MODEL_NAME=$MODEL" >&2
        else
          echo "[hermes-probe] LOCAL_MODEL_NAME=$MODEL" >&2
        fi
        umask 077
        printf 'LOCAL_MODEL_NAME=%s\n' "$MODEL" > "$OUT"
        chown hermes:hermes "$OUT"
        chmod 0440 "$OUT"
      '')
    ];
  };
}
```

### `secrets/hermes.env` (new)

Plaintext shape before encryption:

```
OPENAI_API_KEY=sk-no-key-required
DEEPSEEK_API_KEY=sk-deepseek-...
```

Encrypted with `sops -e -i secrets/hermes.env`. The `.env` extension is matched by the existing `secrets/[^/]+\.(yaml|json|env|...)$` regex in `.sops.yaml`, so it's encrypted to chin39's age key only — same posture as `secrets/hosts.yaml`.

> **Reminder (deferred to post-impl):** This file does not exist yet and the service will not start without it. Create + encrypt as the final step after the module lands.

## 4. Tools declared on hermes' PATH

Mirrors the upstream `nix develop` set, plus the standard agent toolkit:

```nix
extraPackages = with pkgs; [
  # Parity with hermes' upstream dev shell
  python312          # interpreter for ad-hoc scripts (the venv is sealed separately)
  uv                 # for python deps not pre-bundled
  nodejs_22          # node + npm for JS-flavoured MCPs / scripts
  ripgrep
  git
  openssh
  ffmpeg

  # Standard agent-on-a-shell toolkit
  curl
  wget
  jq
  fd
  yq-go              # jq-for-yaml — useful when agent edits its own config
  tree               # readable directory dumps in tool-call outputs
  file               # mime sniffing for downloads
  unzip
  gnutar
  gzip

  # Build tooling — needed if the agent compiles anything
  gnumake
  gcc
  pkg-config

  # Niceties for shell sessions
  bashInteractive
  coreutils-full
  gnused
  gawk
];

extraPythonPackages = ps: with ps; [
  requests
  beautifulsoup4
  httpx
  pydantic
];
```

Adding a tool later: edit `hermes.nix`, `nixos-rebuild switch`, restart. `git log nixos/services/hermes.nix` is the complete history of what the agent has ever had access to.

## 5. `services.hermes-agent.settings` — schema-verified

All keys verified against the hermes flake source at `github:NousResearch/hermes-agent`
revision `44cdf555a83c1d8d605d095442e11efd58089533` (cli-config.yaml.example, hermes_cli/auth.py, agent/model_metadata.py).

```nix
settings = {
  # ── Primary model: local llama.cpp ─────────────────────────────
  # Model name discovered at service start by the ExecStartPre
  # probe; this lets you swap GGUFs on the Windows host without
  # touching nix.
  model = {
    default  = "\${LOCAL_MODEL_NAME}";
    provider = "custom";                          # OpenAI-compatible local endpoint
    base_url = "http://192.168.0.101:8087/v1";
    api_key  = "\${OPENAI_API_KEY}";              # dummy; llama.cpp ignores
  };

  # ── Compression: DeepSeek (named provider, no base_url needed) ──
  # `provider: "deepseek"` is a built-in named provider in hermes
  # (confirmed in hermes_cli/auth.py:309). Ships with hardcoded
  # base_url=https://api.deepseek.com/v1 and reads DEEPSEEK_API_KEY
  # from the env. No extra wiring on our side.
  auxiliary.compression = {
    provider = "deepseek";
    model    = "deepseek-v4-flash";
    timeout  = 30;
  };

  # ── Compression behavior tuning ────────────────────────────────
  compression = {
    enabled        = true;
    threshold      = 0.50;
    target_ratio   = 0.20;
    protect_last_n = 20;
  };

  # ── Slash-command shortcuts (`/model deepseek`, `/model local`) ─
  # Used by the /model tab completion and resolve_alias().
  # Aliases route through resolve_alias BEFORE the models.dev catalog,
  # so they can target endpoints not in the catalog.
  model_aliases = {
    deepseek = {
      model    = "deepseek-v4-flash";
      provider = "deepseek";
    };
    local = {
      model    = "\${LOCAL_MODEL_NAME}";
      provider = "custom";
      base_url = "http://192.168.0.101:8087/v1";
    };
  };

  # ── Terminal: native local execution (no docker isolation) ─────
  # The hermes process IS the boundary; commands run as the
  # `hermes` user under the hardened systemd unit's sandbox.
  terminal = {
    backend = "local";
    cwd     = ".";
    timeout = 180;
  };

  # ── Security: tirith pre-exec scanning ─────────────────────────
  security = {
    tirith_enabled   = true;
    tirith_fail_open = false;
  };
};
```

The `\${VAR}` references resolve at runtime from `$HERMES_HOME/.env`, which sops-nix and the probe script populate. None of the real key material ever lands in `/nix/store`.

## 6. Validation

### Pre-deploy (no privileged commands)

Run from `/home/chin39/shell-config/`:

```bash
# 1. Module evaluation — confirms our schema matches hermes'
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.enable
# expect: true

nix eval .#nixosConfigurations.vm-nix.config.systemd.services.hermes-agent.serviceConfig.User --raw
# expect: hermes

nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.settings.model.provider --raw
# expect: custom

# 2. Build the system closure without activating it
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link
# Builds the entire vm-nix system as a derivation; if anything is
# wrong with the module or our settings, this fails here.

# 3. Confirm the rendered config.yaml looks right
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.settings --json | jq

# 4. Decrypt sops file as a smoke test (after step 7 in §8)
sops -d secrets/hermes.env | head -5
```

All four commands run unprivileged.

### Schema cross-check

Run inside hermes' dev shell — no system change needed:

```bash
nix develop github:NousResearch/hermes-agent --command hermes config check
```

This dumps the live option schema. Cross-reference with §5 — any key we set that hermes doesn't recognize gets logged as a warning.

### Deploy with `test` before `switch`

```bash
# Activate for THIS boot only — reboot reverts.
sudo nixos-rebuild test --flake .#vm-nix

# Verify (next subsection). If anything looks bad, `sudo reboot`.

# Once test looks clean, persist:
sudo nixos-rebuild switch --flake .#vm-nix
```

### Post-deploy verification

```bash
# Service health
systemctl status hermes-agent.service

# Probe ran and resolved the model
cat /run/hermes/discovered.env
# expect: LOCAL_MODEL_NAME=Qwen3.6-...gguf  (or current GGUF)

# Sops decrypted into env
sudo cat /run/secrets/hermes-env | head -5
# expect: OPENAI_API_KEY=...  /  DEEPSEEK_API_KEY=...

# Hermes generated config.yaml from settings
sudo cat /var/lib/hermes/.hermes/config.yaml | head -40

# Recent logs
journalctl -u hermes-agent --since "5 min ago" --no-pager

# CLI smoke tests against each path
hermes config check                          # managed-mode aware
hermes chat "say hi"                         # local model (default)
hermes chat --provider deepseek --model deepseek-v4-flash "say hi"
# or after model_aliases resolution:
hermes chat /model deepseek                  # interactive switch
```

## 7. Failure modes & rollback

| Failure | Symptom | Action |
|---|---|---|
| Sops can't decrypt at activation | `nixos-rebuild` aborts before any service touches the system | confirm `/home/chin39/.config/sops/age/keys.txt` exists and matches recipient in `.sops.yaml`; re-encrypt if rotated |
| Local llama.cpp asleep at start | Probe writes `LOCAL_MODEL_NAME=local-unavailable`; service starts; agent calls fail at use time | wake the box, `sudo systemctl restart hermes-agent` |
| DeepSeek API unreachable | Compression role and `--provider deepseek` calls fail; default keeps working | transient, no service-level action |
| Hardened systemd blocks unexpected path write | Service crashes; journalctl shows `EACCES` | add path to `serviceConfig.ReadWritePaths`; rebuild |
| `model_aliases` schema rejected | Build-time error in step 2 above | drop `model_aliases` for v1 (CLI flags still work); file an issue against hermes |
| Config-validation error on first start | journalctl shows hermes config error | run `hermes config check` from dev shell to dump live schema; fix divergent key; rebuild |

### Rollback paths, in order of cost

1. **Bad config caught at `nixos-rebuild test`** → `sudo reboot`. Zero residue.
2. **Bad config after `switch`** → `sudo nixos-rebuild switch --flake .#vm-nix --rollback`, or pick prior generation from systemd-boot menu.
3. **Bad config committed** → `git revert <sha>`, `nixos-rebuild switch` again.
4. **Sops file corrupted** → `git checkout secrets/hermes.env` to recover encrypted blob.
5. **State directory corrupted** → `sudo systemctl stop hermes-agent`, `sudo rm -rf /var/lib/hermes/.hermes`, `sudo systemctl start hermes-agent`. Workspace under `/var/lib/hermes/workspace` preserved.

## 8. Implementation order

1. Add `hermes-agent` to `flake.nix` inputs
2. `nix flake update hermes-agent` (regenerates `flake.lock`)
3. Create `nixos/services/hermes.nix` with the skeleton from §3
4. Add the import line to `nixos/vm-nix/default.nix`
5. Run pre-deploy validation from §6 — nothing is on the system yet
6. **`nixos-rebuild build --flake .#vm-nix`** to confirm the build succeeds without activating
7. **Reminder fires:** create `secrets/hermes.env` plaintext, run `sops -e -i secrets/hermes.env`, verify with `sops -d`
8. `sudo nixos-rebuild test --flake .#vm-nix`, run post-deploy verification
9. If clean, `sudo nixos-rebuild switch --flake .#vm-nix`
10. Commit all five files together with a message linking back to this spec

## 9. Out-of-scope follow-ups

- Wire MCP servers (Telegram, Drive, GitHub) — each is a 5-line block in `services.hermes-agent.mcpServers` plus an env var in `secrets/hermes.env`
- Add `documents = { "USER.md" = ./hermes-user.md; }` once the agent has been running long enough to know what context it lacks
- Disk-fill protection on `/var/lib/hermes/workspace`
- Once local llama.cpp's per-slot context is fixed (currently 51,200 from `--parallel 4` math), revisit using `auxiliary.compression.provider = "custom"` to keep compression local and cut DeepSeek cost on long sessions
- Optional: wire hermes' `provider_overrides` for a longer timeout against the local server (it cold-starts slowly)

## 10. Verified facts

This design has been validated against the hermes-agent source code (revision `44cdf555a83c1d8d605d095442e11efd58089533`):

| Claim | Source |
|---|---|
| `services.hermes-agent.{enable, settings, environmentFiles, extraPackages, extraPythonPackages, addToSystemPackages, restart, restartSec}` exist as options | `nix/nixosModules.nix:200, 252, 270, 455, 490, 527, 515, 521` |
| `model.{default, provider, base_url, api_key}` are the canonical primary-model keys | `cli-config.yaml.example:9, 42, 46, 45` |
| `provider: "deepseek"` is a built-in named provider with `inference_base_url=https://api.deepseek.com/v1` and `DEEPSEEK_API_KEY` env var | `hermes_cli/auth.py:309-316` |
| `deepseek-v4-flash` has 1M context window | `agent/model_metadata.py:187` |
| `auxiliary.compression.{provider, model, timeout}` is the pin-a-model-for-compression mechanism | `cli-config.yaml.example:409-414` |
| `compression.{enabled, threshold, target_ratio, protect_last_n}` exist as top-level tuning knobs | `cli-config.yaml.example:341-359` |
| `model_aliases.<name>.{model, provider, base_url}` is the slash-command shortcut tuple | `cli-config.yaml.example:1004-1014` |
| `terminal.{backend, cwd, timeout}` confirmed for `backend = "local"` | `cli-config.yaml.example:158-163` |
| `security.{tirith_enabled, tirith_fail_open}` confirmed | `cli-config.yaml.example:290-294` |
| Native systemd hardening: `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp` applied automatically | docs (https://hermes-agent.nousresearch.com/docs/getting-started/nix-setup) |
| `environmentFiles` contents merged into `$HERMES_HOME/.env` at activation; hermes reads on every startup | `nix/nixosModules.nix:23, 273-277` |

Keys NOT in the schema (removed from earlier drafts): `model.aliases.<name>` (use `model_aliases` at top level instead), `approvals.{mode, timeout}` (don't exist).
