# Hermes Agent Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up Hermes Agent as a managed, declarative NixOS service on `vm-nix`, with the local llama.cpp server (192.168.0.101:8087) as default model and DeepSeek (`deepseek-v4-flash`) as compression model + `/model` swap target.

**Architecture:** Native systemd (no container), hardened by hermes' built-in sandbox (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`). Secrets via sops-nix using chin39's existing user age key. Runtime model-name discovery via `ExecStartPre` probe of llama.cpp's `/v1/models`. All agent tooling declared in `extraPackages`.

**Tech Stack:** NixOS (nixos-unstable), hermes-agent flake `github:NousResearch/hermes-agent`, sops-nix (already in repo), systemd, dotenv-format secrets.

**Spec:** `docs/superpowers/specs/2026-05-10-hermes-service-design.md`

**Target repo:** `/home/chin39/shell-config`

---

## File map

| File | Action | Purpose |
|---|---|---|
| `flake.nix` | Edit | Add `hermes-agent` flake input following the existing input pattern |
| `flake.lock` | Regenerated | Mechanical, by `nix flake update hermes-agent` |
| `nixos/services/hermes.nix` | Create | The new module: sops secret, `services.hermes-agent` config, systemd ExecStartPre probe override |
| `nixos/vm-nix/default.nix` | Edit | One-line addition to the `imports` list |
| `secrets/hermes.env` | Create (sops) | Two API key env vars (`OPENAI_API_KEY=sk-no-key-required`, real `DEEPSEEK_API_KEY`), sops-encrypted to chin39's age key |

Single-responsibility: the hermes module file contains everything related to hermes (sops secret, service config, systemd overrides). No splitting into multiple files — the module is ~110 lines and stays well under the codebase's 800-line cap.

---

## Conventions used in this plan

- Every command is run from `/home/chin39/shell-config` unless explicitly stated otherwise.
- All `git commit` messages end with `Signed-off-by: chinqrw@gmail.com` per the user's repo policy. Per the local vm-nix rule, **no** `Co-Authored-By: Claude` or AI-related lines.
- Never `git push` automatically. Each commit stays local until the user pushes manually.
- Use bullet points in commit message bodies, not paragraphs.
- After every code change, run the verification command and confirm the expected output **before** moving on. If output diverges, stop and diagnose — don't paper over it.

---

## Task 1: Add hermes-agent input to flake.nix

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock` (regenerated)

- [ ] **Step 1: Read the current `inputs` block in flake.nix**

```bash
sed -n '26,100p' flake.nix
```

Confirm the existing input pattern uses `inputs.nixpkgs.follows = "nixpkgs"` for inputs that take a nixpkgs argument.

- [ ] **Step 2: Edit flake.nix to add the hermes-agent input**

Insert this block alphabetically with the other inputs (place after `hardware.url = "github:NixOS/nixos-hardware";` for cleanliness, but exact location doesn't affect behavior):

```nix
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 3: Verify the file still parses**

```bash
nix-instantiate --parse flake.nix > /dev/null && echo "OK"
```

Expected: `OK`

If you get a syntax error, fix the brace/comma you added before continuing.

- [ ] **Step 4: Update the flake lock to fetch hermes-agent**

```bash
nix flake update hermes-agent 2>&1 | tail -10
```

Expected: a "Locked input" line referencing `github:NousResearch/hermes-agent`. The first run also unpacks the source — takes 5–30 seconds depending on network.

- [ ] **Step 5: Confirm the new input is reachable**

```bash
nix eval .#inputs.hermes-agent.lastModifiedDate --raw 2>&1 | head -1
```

Expected: a string like `20260207042405` (some recent ISO-style date). Any number means the input resolved.

- [ ] **Step 6: Commit**

```bash
git add flake.nix flake.lock
git commit -m "$(cat <<'EOF'
flake: add hermes-agent input

- Adds github:NousResearch/hermes-agent as a flake input
- nixpkgs follows the repo-level nixos-unstable pin

Signed-off-by: chinqrw@gmail.com
EOF
)"
git log --oneline -1
```

Expected: a single new commit with subject `flake: add hermes-agent input`.

---

## Task 2: Create the hermes.nix module file

**Files:**
- Create: `nixos/services/hermes.nix`

This is the only "new file with substantial content" task. The file is created in a single step (since intermediate partial states aren't independently testable for nix modules), then verified to parse. Wiring it into vm-nix happens in Task 3.

- [ ] **Step 1: Verify the target path doesn't already exist**

```bash
test -e nixos/services/hermes.nix && echo "EXISTS — STOP" || echo "OK to create"
```

Expected: `OK to create`. If it exists, stop and ask the user — something's wrong with the plan state.

- [ ] **Step 2: Create the file**

Write `nixos/services/hermes.nix` with this exact content:

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  # ── Sops secret: hermes-env ─────────────────────────────────────
  # Encrypted dotenv file at secrets/hermes.env. sops-nix decrypts
  # at activation (running as root, reading chin39's user age key)
  # and writes plaintext to /run/secrets/hermes-env owned by the
  # hermes service user.
  sops.secrets."hermes-env" = {
    sopsFile = ../../secrets/hermes.env;
    format = "dotenv";
    owner = "hermes";
    mode = "0400";
  };

  # ── Service ─────────────────────────────────────────────────────
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    environmentFiles = [
      config.sops.secrets."hermes-env".path
      "/run/hermes/discovered.env"
    ];

    settings = {
      # Primary model: local llama.cpp on the LAN.
      # Model name discovered at service start by the probe below;
      # do not hardcode it. Swap GGUFs on the server, restart hermes.
      model = {
        default = "\${LOCAL_MODEL_NAME}";
        provider = "custom";
        base_url = "http://192.168.0.101:8087/v1";
        api_key = "\${OPENAI_API_KEY}";
      };

      # Compression: DeepSeek named provider (built-in base_url +
      # DEEPSEEK_API_KEY env var; no extra wiring needed).
      auxiliary.compression = {
        provider = "deepseek";
        model = "deepseek-v4-flash";
        timeout = 30;
      };

      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
        protect_last_n = 20;
      };

      model_aliases = {
        deepseek = {
          model = "deepseek-v4-flash";
          provider = "deepseek";
        };
        local = {
          model = "\${LOCAL_MODEL_NAME}";
          provider = "custom";
          base_url = "http://192.168.0.101:8087/v1";
        };
      };

      terminal = {
        backend = "local";
        cwd = ".";
        timeout = 180;
      };

      security = {
        tirith_enabled = true;
        tirith_fail_open = false;
      };
    };

    extraPackages = with pkgs; [
      # Parity with hermes' upstream dev shell
      python312
      uv
      nodejs_22
      ripgrep
      git
      openssh
      ffmpeg

      # Standard agent toolkit
      curl
      wget
      jq
      fd
      yq-go
      tree
      file
      unzip
      gnutar
      gzip

      # Build tooling
      gnumake
      gcc
      pkg-config

      # Shell niceties
      bashInteractive
      coreutils-full
      gnused
      gawk
    ];

    extraPythonPackages =
      ps: with ps; [
        requests
        beautifulsoup4
        httpx
        pydantic
      ];

    restart = "always";
    restartSec = 5;
  };

  # ── Systemd overrides: probe llama.cpp for the live model name ──
  # Runs before the gateway. 5s timeout, graceful fallback writes
  # LOCAL_MODEL_NAME=local-unavailable so the service still starts
  # when the model server is asleep.
  systemd.services.hermes-agent = {
    serviceConfig.RuntimeDirectory = "hermes";
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

- [ ] **Step 3: Verify the file parses as nix syntax**

```bash
nix-instantiate --parse nixos/services/hermes.nix > /dev/null && echo "OK"
```

Expected: `OK`. If you get a parse error, the file has a typo — fix and re-run.

- [ ] **Step 4: Confirm line count is reasonable (sanity check)**

```bash
wc -l nixos/services/hermes.nix
```

Expected: ~140 lines. Significantly fewer means content was truncated.

- [ ] **Step 5: Commit**

```bash
git add nixos/services/hermes.nix
git commit -m "$(cat <<'EOF'
nixos/services/hermes: add hermes-agent service module

- New file declaring services.hermes-agent for vm-nix
- Uses native systemd (no container) with hardened defaults
- Settings: local llama.cpp default, DeepSeek compression
- Sops secret: secrets/hermes.env (dotenv format)
- ExecStartPre probe writes LOCAL_MODEL_NAME from llama.cpp /v1/models
- extraPackages provides full agent toolkit
- Not yet imported by any host; Task 3 wires it into vm-nix

Signed-off-by: chinqrw@gmail.com
EOF
)"
git log --oneline -1
```

Expected: a new commit `nixos/services/hermes: add hermes-agent service module`.

---

## Task 3: Wire hermes.nix into vm-nix and verify whole-system build

**Files:**
- Modify: `nixos/vm-nix/default.nix:13-35` (the existing `imports` list)

- [ ] **Step 1: Read the current imports list**

```bash
sed -n '13,35p' nixos/vm-nix/default.nix
```

Confirm the existing pattern (one path per line, relative to current file).

- [ ] **Step 2: Add the new import line**

Edit `nixos/vm-nix/default.nix`. Add this line at the end of the `imports = [ ... ]` list, before the closing `]`:

```nix
    ../services/hermes.nix
```

The full block after edit should look like (showing relevant context):

```nix
  imports = [
    inputs.hardware.nixosModules.common-cpu-amd
    ./hardware.nix
    ./wireguard.nix
    ./container/jellyfin.nix
    ../services/github-runners.nix
    ../services/samba/wsl-server.nix
    (import ../services/aria2.nix {
      inherit
        config
        pkgs
        username
        sharedGroup
        ;
    })
    ../services/qbittorrent.nix
    ../services/cachix-deploy.nix
    ../services/nix-serve.nix
    ../services/factorio.nix
    ./kernel.nix
    ../services/hermes.nix
    # ./rclone.nix
    # ./proxy.nix
  ];
```

- [ ] **Step 3: Confirm the file still parses**

```bash
nix-instantiate --parse nixos/vm-nix/default.nix > /dev/null && echo "OK"
```

Expected: `OK`.

- [ ] **Step 4: Confirm the option is now set on vm-nix**

```bash
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.enable
```

Expected: `true`. If you get an error like `attribute 'hermes-agent' missing`, the import line didn't take — re-check Task 3 Step 2.

- [ ] **Step 5: Confirm a few other settings landed correctly**

```bash
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.settings.model.provider --raw
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.settings.auxiliary.compression.provider --raw
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.settings.terminal.backend --raw
```

Expected, in order: `custom`, `deepseek`, `local`.

- [ ] **Step 6: Build the full system closure WITHOUT activating**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -20
```

Expected: the build completes without errors. This downloads anything missing (hermes-agent's uv2nix-built python venv is the heaviest dependency; can take several minutes on a cold cache). If the build succeeds, every piece of the module is structurally valid.

If the build fails, read the error. Common failures:
- `error: attribute 'X' missing` — schema mismatch, a settings key isn't recognized by hermes' module. Fix in `hermes.nix`.
- `error: cannot coerce ... to a string` — type mismatch, usually in `extraPackages` or `extraPythonPackages`. Fix in `hermes.nix`.
- `error: file 'secrets/hermes.env' does not exist` — sops-nix is checking at build time. This shouldn't happen for our setup but if it does, comment out the sops block temporarily and proceed; we'll create the file in Task 4.

- [ ] **Step 7: Commit**

```bash
git add nixos/vm-nix/default.nix
git commit -m "$(cat <<'EOF'
nixos/vm-nix: import hermes service module

- Adds ../services/hermes.nix to vm-nix imports list
- Activates services.hermes-agent on vm-nix
- nixosConfigurations.vm-nix builds successfully (verified
  via nix build --no-link)

Signed-off-by: chinqrw@gmail.com
EOF
)"
git log --oneline -1
```

---

## Task 4: Create the plaintext secrets file (DO NOT COMMIT)

**Files:**
- Create: `secrets/hermes.env` (plaintext, will be sops-encrypted in Task 5)

> **WARNING — pre-encryption window.** This task creates the secrets file in plaintext. It must be encrypted (Task 5) before being committed or read from another shell. Do not `git add` it during this task. Do not read it into pastebin/screenshot/anywhere else.

- [ ] **Step 1: Verify your DeepSeek API key is at hand**

You need a real `DEEPSEEK_API_KEY` (a string starting with `sk-`). If you don't have one, get it from https://platform.deepseek.com/ before continuing — there's no point creating the file without the real key.

- [ ] **Step 2: Verify the secrets dir exists**

```bash
ls -la secrets/
```

Expected: directory exists, contains `hosts.yaml` and other encrypted files. The new file goes alongside.

- [ ] **Step 3: Write the plaintext file**

Replace `<YOUR-REAL-DEEPSEEK-KEY>` below with your actual DeepSeek API key, then run:

```bash
cat > secrets/hermes.env <<'EOF'
OPENAI_API_KEY=sk-no-key-required
DEEPSEEK_API_KEY=<YOUR-REAL-DEEPSEEK-KEY>
EOF
```

- [ ] **Step 4: Verify the file content (and confirm there's no leak)**

```bash
wc -l secrets/hermes.env
# Expected: 2
head -1 secrets/hermes.env
# Expected: OPENAI_API_KEY=sk-no-key-required
```

Do not `cat` the second line into the terminal — your DeepSeek key would be in your shell history.

- [ ] **Step 5: Confirm git sees the file as untracked (not staged)**

```bash
git status secrets/hermes.env
```

Expected: `Untracked files: secrets/hermes.env` (in red). If it's already staged, run `git restore --staged secrets/hermes.env` immediately.

> **STOP — do not commit yet.** Move on to Task 5 to encrypt before committing.

---

## Task 5: Encrypt secrets/hermes.env with sops and commit

**Files:**
- Encrypt-in-place: `secrets/hermes.env`

- [ ] **Step 1: Confirm sops can find your age key**

```bash
test -f /home/chin39/.config/sops/age/keys.txt && echo "OK key file exists"
```

Expected: `OK key file exists`. If the file is missing, sops will fail at the next step — recover the key first.

- [ ] **Step 2: Verify the .sops.yaml regex covers your file**

```bash
grep -n "secrets/\[" .sops.yaml
```

Expected output includes:

```
4:  - path_regex: secrets/[^/]+\.(yaml|json|env|ini|sops|conf)$
```

The `.env` extension is matched by the chin39-only rule, which is what we want.

- [ ] **Step 3: Encrypt in place**

```bash
sops -e -i secrets/hermes.env
```

No expected output on success. If you get `Failed to get the data key required to decrypt the SOPS file`, your age key doesn't match the recipient — stop and diagnose.

- [ ] **Step 4: Verify the file is now encrypted**

```bash
head -1 secrets/hermes.env
```

Expected: a line starting with `OPENAI_API_KEY=ENC[AES256_GCM,data:...` — the value is encrypted, the key name stays in plaintext (this is how sops dotenv format works).

If you see `OPENAI_API_KEY=sk-no-key-required` still, the encryption didn't happen. Re-check step 3.

- [ ] **Step 5: Verify decryption works**

```bash
sops -d secrets/hermes.env | head -1
```

Expected: `OPENAI_API_KEY=sk-no-key-required` (the original plaintext). Round-trip confirmed.

- [ ] **Step 6: Commit the encrypted file**

```bash
git add secrets/hermes.env
git status secrets/hermes.env
# Expected: shows as "new file" with encrypted content visible in diff
git diff --cached secrets/hermes.env | head -20
# Expected: encrypted blob, no plaintext key visible
git commit -m "$(cat <<'EOF'
secrets: add hermes.env (sops, dotenv)

- New encrypted file with OPENAI_API_KEY (dummy) and DEEPSEEK_API_KEY
- Encrypted to chin39 age key per the secrets/*.env rule in .sops.yaml
- Read by services.hermes-agent.environmentFiles at activation

Signed-off-by: chinqrw@gmail.com
EOF
)"
git log --oneline -1
```

Expected: a new commit `secrets: add hermes.env (sops, dotenv)`. The diff in the commit should show only encrypted blobs, no plaintext keys.

> **REMINDER (Task #7 in the brainstorming flow):** This task closes out the deferred secrets-file reminder. The reminder is now resolved.

---

## Task 6: Activate via `nixos-rebuild test` and run post-deploy verifications

**Files touched:** None — this task only activates already-committed configuration.

This task uses sudo. Everything else stays the same.

- [ ] **Step 1: Re-run the closure build to confirm everything still composes**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Expected: build succeeds with no error. Now that `secrets/hermes.env` exists, even a strict pre-build sops check would pass.

- [ ] **Step 2: Activate for this boot only**

```bash
sudo nixos-rebuild test --flake .#vm-nix 2>&1 | tail -30
```

Expected: ends with `activation: setting up tmpfiles` then a success line. Watch for warnings — sops-nix prints if any secrets are missing or owner mismatches.

- [ ] **Step 3: Verify the systemd service is up**

```bash
systemctl status hermes-agent.service --no-pager 2>&1 | head -20
```

Expected: `Active: active (running)`. If `Active: failed`, jump to Step 7 (logs) immediately.

- [ ] **Step 4: Verify the probe ran and discovered the model**

```bash
cat /run/hermes/discovered.env
```

Expected: `LOCAL_MODEL_NAME=Qwen3.6-...gguf` (or whatever GGUF is currently loaded on the Windows box at 192.168.0.101). If you see `LOCAL_MODEL_NAME=local-unavailable`, the model server is asleep — wake it and `sudo systemctl restart hermes-agent`.

- [ ] **Step 5: Verify sops decrypted the env file**

```bash
sudo cat /run/secrets/hermes-env | head -5
```

Expected: two lines starting `OPENAI_API_KEY=` and `DEEPSEEK_API_KEY=` with plaintext values. If the file doesn't exist, sops failed during activation — check `journalctl -u sops-install-secrets.service`.

- [ ] **Step 6: Verify hermes generated config.yaml from settings**

```bash
sudo head -40 /var/lib/hermes/.hermes/config.yaml
```

Expected: yaml with `model.base_url: http://192.168.0.101:8087/v1`, `auxiliary.compression.provider: deepseek`, etc. If `config.yaml` doesn't exist, the gateway hasn't initialized — check service logs.

- [ ] **Step 7: Tail the service logs**

```bash
journalctl -u hermes-agent --since "5 min ago" --no-pager 2>&1 | tail -50
```

Expected: probe logs (`[hermes-probe] LOCAL_MODEL_NAME=...`), gateway startup, no `ERROR` or `Traceback` lines. If you see Python tracebacks, capture the error and stop — fix in `hermes.nix` before going further.

- [ ] **Step 8: CLI smoke test against the local model (default)**

```bash
hermes config check 2>&1 | head -20
```

Expected: a config dump or "OK" message. In managed mode some commands may print "this is managed by NixOS" — that's fine, the check still validates settings.

```bash
hermes chat "say hi in three words" 2>&1 | tail -10
```

Expected: a model response with three words. Latency under 5s on warm local server.

- [ ] **Step 9: CLI smoke test against DeepSeek**

```bash
hermes chat --provider deepseek --model deepseek-v4-flash "say hi in three words" 2>&1 | tail -10
```

Expected: a model response. DeepSeek round-trip via the proxy at 192.168.0.240:10809.

- [ ] **Step 10: Test the model_aliases shortcut**

```bash
# In an interactive `hermes chat` session:
hermes chat <<EOF
/model deepseek
say hi
EOF
```

Expected: the `/model deepseek` line accepts the swap; the response comes from DeepSeek.

- [ ] **Step 11: Decide go/no-go**

If steps 3–10 all passed: **green light** — proceed to Task 7 to persist.

If anything failed: **stop**. Reboot the host (`sudo reboot`) — `nixos-rebuild test` doesn't update the boot loader, so the prior generation will come back. Diagnose with the failed-task evidence in hand, edit `hermes.nix` accordingly, recommit, and re-run Task 6.

---

## Task 7: Persist the activation with `nixos-rebuild switch`

**Files touched:** None — same closure as Task 6, this just makes it survive a reboot.

- [ ] **Step 1: Persist the activation**

```bash
sudo nixos-rebuild switch --flake .#vm-nix 2>&1 | tail -15
```

Expected: same activation log as Task 6 Step 2, plus a "updating GRUB / systemd-boot" line that wasn't there before.

- [ ] **Step 2: Confirm the new generation is the default**

```bash
sudo nixos-rebuild list-generations 2>&1 | tail -5
```

Expected: the latest generation is marked `(current)`.

- [ ] **Step 3: Final post-deploy smoke**

```bash
systemctl is-active hermes-agent
# Expected: active
hermes chat "say ok if you are alive" 2>&1 | tail -3
# Expected: a response that says "ok"
```

- [ ] **Step 4: No commit (nothing changed in git)**

This task only persists already-committed state. No files were modified. Skip the commit.

If you want a marker commit linking back to the design and plan, optionally:

```bash
git commit --allow-empty -m "$(cat <<'EOF'
chore: hermes-agent service activated on vm-nix

- nixos-rebuild switch completed, hermes-agent.service active
- Spec: docs/superpowers/specs/2026-05-10-hermes-service-design.md
- Plan: docs/superpowers/plans/2026-05-10-hermes-service-implementation.md

Signed-off-by: chinqrw@gmail.com
EOF
)"
```

(Optional, your call.)

---

## Rollback procedures

If anything goes wrong at any step, in escalating order of cost:

1. **`nixos-rebuild test` failed (Task 6)** → `sudo reboot`. Zero residue. Prior generation still active. Edit `hermes.nix`, re-commit, retry.

2. **`switch` made things worse (Task 7)** → `sudo nixos-rebuild switch --flake .#vm-nix --rollback`. About 5 seconds. Or pick the previous generation from systemd-boot at next boot.

3. **Bad commit needs to come out** → `git revert <sha>`, then `nixos-rebuild switch` again. The flake is the source of truth.

4. **Sops file got corrupted / re-encrypted to wrong key** → `git checkout secrets/hermes.env` recovers the prior encrypted blob. Sops gives no useful error if the wrong key is used — recovery is via git, not via decryption attempts.

5. **State directory corrupted** → `sudo systemctl stop hermes-agent`, `sudo rm -rf /var/lib/hermes/.hermes`, `sudo systemctl start hermes-agent`. Workspace under `/var/lib/hermes/workspace` is preserved; only generated config + env blob get refreshed.

---

## Self-review against spec

Cross-checking every spec section against tasks:

| Spec section | Plan coverage |
|---|---|
| §1 Goal & Non-goals | Tasks 1–7 implement the goal; non-goals (MCP, GPU, llm.nix edits) explicitly absent |
| §2 Architecture | Task 2 creates the module that produces the architecture; Task 3 wires it; Task 6 verifies it |
| §3 Files | Task 1 (flake.nix), Task 2 (hermes.nix), Task 3 (vm-nix/default.nix), Tasks 4+5 (secrets/hermes.env), flake.lock regenerated in Task 1 |
| §4 Tools (extraPackages) | Task 2 Step 2, full list embedded |
| §5 Settings (model, auxiliary, compression, model_aliases, terminal, security) | Task 2 Step 2, full block embedded |
| §6 Validation (pre-deploy, schema cross-check, test before switch, post-deploy) | Pre-deploy in Task 3 Steps 4–6; deploy with test in Task 6; post-deploy in Task 6 Steps 3–10; persist in Task 7 |
| §7 Failure modes & rollback | "Rollback procedures" section above; Task 6 Step 7 covers troubleshooting |
| §8 Implementation order | Matches Task 1→7 ordering |
| §9 Out-of-scope follow-ups | Explicitly NOT in plan |
| §10 Verified facts | Schema-correctness already baked into the settings block in Task 2 Step 2 |

No gaps.

**Placeholder scan:** searched for "TBD", "TODO", "later", "appropriate", "as needed". None present in this plan.

**Type / name consistency:** `hermes`, `hermes-agent`, `services.hermes-agent`, `LOCAL_MODEL_NAME`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, `secrets/hermes.env` — every reference uses the same exact name across all tasks.

---

## Out of scope (explicit non-goals — do not implement here)

- MCP servers (Telegram, Drive, GitHub) — separate plan when needed.
- `documents` field for USER.md / agent context — wait until the agent has been live and we know what it actually lacks.
- Disk-fill protection on `/var/lib/hermes/workspace`.
- Provider-overrides (per-endpoint timeouts, retry tuning).
- Switching `auxiliary.compression` back to local once llama.cpp's per-slot context is fixed.

These come in follow-up plans, not this one.
