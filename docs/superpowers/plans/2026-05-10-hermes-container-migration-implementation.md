# Hermes Container Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `services.hermes-agent` on `vm-nix` from native systemd mode to docker container mode (`ubuntu:24.04`, `hostUsers = [ "chin39" ]`). Drop the four host-integration patches that container mode subsumes. Replace the runtime model probe with a direct-`.env`-edit mechanism that fits container mode.

**Architecture:** Container mode installs a CLI router on chin39's `$PATH` instead of the real hermes binary; chin39's invocations transparently `docker exec` into the gateway container and run as the container's hermes user. State persists via bind mount of `/var/lib/hermes` → `/data`. Probe runs on host as `ExecStartPre`, edits `/var/lib/hermes/.hermes/.env` directly (which is the same file the container reads via its bind mount).

**Tech Stack:** NixOS (nixos-unstable), `services.hermes-agent` (hermes-agent flake rev `44cdf555`), Docker rootful (already enabled on vm-nix), sops-nix.

**Spec:** `docs/superpowers/specs/2026-05-10-hermes-container-migration-design.md`

**Target repo:** `/home/chin39/shell-config`

---

## File map

| File | Action | Purpose |
|---|---|---|
| `nixos/services/hermes.nix` | Full rewrite (replace contents) | The migration. ~246 lines → ~110 lines. Adds `container.*`, drops 4 host-integration patches, replaces probe mechanism. |

No other files change. `nixos/vm-nix/default.nix` already imports `../services/hermes.nix`; nothing to touch there. `secrets/hermes.env` stays as-is. `flake.nix` and `flake.lock` are unchanged.

---

## Conventions used in this plan

- All commands run from `/home/chin39/shell-config` unless stated otherwise.
- All `git commit` messages end with `Signed-off-by: chinqrw@gmail.com` per repo policy. **No** `Co-Authored-By: Claude` or AI-related lines.
- Bullet points in commit message bodies, not paragraphs.
- Never `git push` automatically.
- After every code change, run the verification command and confirm expected output before moving on.

---

## Task 1: Replace `hermes.nix` with the container-mode version

**Files:**
- Modify (full rewrite): `/home/chin39/shell-config/nixos/services/hermes.nix`

This single Write operation produces the post-migration state of the file. We verify with `nix-instantiate --parse`, then `nix eval`, then a full closure build, then commit.

- [ ] **Step 1: Confirm pre-migration state of the file**

```bash
wc -l /home/chin39/shell-config/nixos/services/hermes.nix
```

Expected: between 240 and 260 lines (current state is 246 lines as of commit `f43e33f`). If the file is significantly smaller, someone may have already edited it — STOP and report.

- [ ] **Step 2: Write the new file content**

Use the `Write` tool to replace `/home/chin39/shell-config/nixos/services/hermes.nix` with this exact content:

```nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  deepseekModel = "deepseek-v4-flash";
in
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

    # Run hermes inside an Ubuntu 24.04 container. With both
    # container.enable and addToSystemPackages = true, the binary
    # installed on chin39's PATH is the upstream CLI ROUTER, not
    # the real hermes — every invocation docker-execs into this
    # container and runs as the container's hermes user. That
    # eliminates the user-mismatch collisions the previous
    # native-mode setup suffered from.
    container = {
      enable    = true;
      backend   = "docker";
      image     = "ubuntu:24.04";
      hostUsers = [ "chin39" ];
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
    ];

    settings = {
      # Primary model: local llama.cpp on the LAN.
      # ${LOCAL_MODEL_NAME} resolves at gateway startup from the
      # .env file. The probe (below) writes that variable into the
      # bind-mounted .env on every service start, so swapping a GGUF
      # on the Windows box + `sudo systemctl restart hermes-agent`
      # is enough to pick up the new model — no nixos-rebuild needed.
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
        model = deepseekModel;
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
          model = deepseekModel;
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
      # Parity with hermes' upstream dev shell.
      # python312 deliberately omitted: the sealed uv2nix venv
      # provides Python via $HERMES_PYTHON; adding python312 here
      # would pull python3.12-3.12.13-doc.drv (via
      # environment.extraOutputsToInstall = ["man" "info" "doc"])
      # which fails on a sphinx/docutils-0.22.4 incompatibility.
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

    # extraPythonPackages are for user-developed plugins only.
    # requests, httpx, pydantic are already in hermes' sealed
    # uv2nix venv; beautifulsoup4 pulls typing-extensions
    # transitively which collides with the venv. Empty list.
    extraPythonPackages = [ ];

    restart = "always";
    restartSec = 5;
  };

  # ── Runtime model probe ─────────────────────────────────────────
  # Probe llama.cpp on the host before each container start; write
  # LOCAL_MODEL_NAME directly into /var/lib/hermes/.hermes/.env
  # (which the container sees as /data/.hermes/.env via the bind
  # mount). The container's gateway re-reads .env on startup and
  # picks up the new value. Idempotent: sed-deletes any prior
  # LOCAL_MODEL_NAME line before appending fresh.
  #
  # Self-healing: nixos-rebuild's activation script overwrites .env
  # by re-merging environmentFiles — wiping our probe addition. The
  # NEXT service start re-runs ExecStartPre which re-adds the line,
  # so the system converges back to a correct state automatically.
  systemd.services.hermes-agent.serviceConfig.ExecStartPre = [
    (pkgs.writeShellScript "hermes-probe-local-model" ''
      set -u
      ENV_FILE=/var/lib/hermes/.hermes/.env

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

      if [ -f "$ENV_FILE" ]; then
        ${pkgs.gnused}/bin/sed -i '/^LOCAL_MODEL_NAME=/d' "$ENV_FILE"
        echo "LOCAL_MODEL_NAME=$MODEL" >> "$ENV_FILE"
      fi
    '')
  ];
}
```

Note these intentional differences from the previous file:
- `container.*` block added inside `services.hermes-agent`
- `environmentFiles` list shrunk to just the sops path (no `/run/hermes/discovered.env`)
- The `users.users.chin39.extraGroups = [ "hermes" ]` block is **removed**
- The `security.sudo.extraRules` block is **removed**
- The `systemd.tmpfiles.rules` block is **removed**
- The `system.activationScripts.hermesStatePerms` block is **removed**
- The `systemd.services.hermes-agent.serviceConfig.RuntimeDirectory*` lines are **removed**
- The `ExecStartPre` script body is rewritten to edit `/var/lib/hermes/.hermes/.env` directly instead of writing `/run/hermes/discovered.env`

The `\${LOCAL_MODEL_NAME}` and `\${OPENAI_API_KEY}` sequences (with backslash before `${`) are intentional — they prevent nix from interpolating those at build time so the `${VAR}` survives into the rendered config.yaml as a literal env-var reference for hermes to substitute at runtime. **Do not "fix" them.**

The `${pkgs.curl}/bin/curl`, `${pkgs.jq}/bin/jq`, `${pkgs.gnused}/bin/sed` sequences (no backslash) inside the shell script ARE meant to be nix-interpolated at build time — they bake absolute store paths into the script. Leave those without backslash.

- [ ] **Step 3: Verify the file parses as nix syntax**

```bash
nix-instantiate --parse /home/chin39/shell-config/nixos/services/hermes.nix > /dev/null && echo PARSE_OK
```

Expected: `PARSE_OK`.

If parse fails, the Write missed something. Re-check exact content from Step 2.

- [ ] **Step 4: Sanity-check line count**

```bash
wc -l /home/chin39/shell-config/nixos/services/hermes.nix
```

Expected: between 100 and 130 lines. If significantly larger, content from Step 2 was truncated and the new file still includes some old content.

- [ ] **Step 5: Verify the migration actually changes the relevant nix options**

Run from `/home/chin39/shell-config`:

```bash
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.enable
```

Expected: `true`.

```bash
nix eval --raw .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.image
```

Expected: `ubuntu:24.04`.

```bash
nix eval --json .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.hostUsers
```

Expected: `["chin39"]`.

```bash
nix eval --json .#nixosConfigurations.vm-nix.config.users.users.chin39.extraGroups | jq 'index("hermes")'
```

Expected: `null` (chin39 is no longer in the hermes group at the nix-config level — though existing OS group membership persists until activation runs).

```bash
nix eval --json .#nixosConfigurations.vm-nix.config.security.sudo.extraRules | jq '[.[] | select(.users[]? == "chin39" and (.commands[]?.command // "" | test("hermes")))] | length'
```

Expected: `0` (the sudoers rule for hermes is gone).

```bash
nix eval --json .#nixosConfigurations.vm-nix.config.systemd.tmpfiles.rules | jq '[.[] | select(test("hermes/cron"))] | length'
```

Expected: `0` (tmpfiles rules for cron tree are gone).

If any of these returns the WRONG value, the file contents from Step 2 weren't applied correctly — re-check.

- [ ] **Step 6: Build the full system closure WITHOUT activating**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -5
```

Use a 600000 ms timeout (10 min). Expected: build completes with no `error:` lines.

If the build fails, READ THE ERROR. Common causes:
- `error: attribute 'X' missing` in container.* block — the option name is wrong; cross-check against `/nix/store/2x9ll13myid2kqrjlbnj096hcx53s2gd-vw8lan7g3yvpd8mhbwx66878jc7pjlkm-source/nix/nixosModules.nix:540` (look for `container = lib.mkOption` ... `submodule { options = { ... } }`).
- `error: file 'secrets/hermes.env' does not exist` — the secrets file got deleted somehow. Check `git status secrets/hermes.env`; restore from git if needed.
- Anything else — STOP and report BLOCKED with the error and the last 30 lines of `nix build` output.

- [ ] **Step 7: Commit**

```bash
cd /home/chin39/shell-config && git add nixos/services/hermes.nix && git commit -m "$(cat <<'EOF'
nixos/services/hermes: migrate to container mode

- Switch services.hermes-agent.container.enable to true with
  ubuntu:24.04 backend and chin39 in hostUsers (creates the
  ~/.hermes symlink and installs CLI router on chin39's PATH)
- Drop host-integration patches that container mode subsumes:
  - users.users.chin39.extraGroups = [ "hermes" ]
  - security.sudo.extraRules (passwordless sudo -u hermes hermes)
  - systemd.tmpfiles.rules for cron tree
  - system.activationScripts.hermesStatePerms (chown sweep)
- Replace ExecStartPre probe to write LOCAL_MODEL_NAME directly
  into /var/lib/hermes/.hermes/.env (which is /data/.hermes/.env
  inside the container via the bind mount), instead of the old
  /run/hermes/discovered.env mechanism (which depended on
  activation-time environmentFiles merging that didn't fire on
  pure systemctl restart)
- Net diff: ~135 lines smaller; eliminates the entire class of
  chin39-vs-hermes-user permission collisions

Resolves: the recurring permission-fixup churn diagnosed in
docs/superpowers/specs/2026-05-10-hermes-container-migration-design.md

Signed-off-by: chinqrw@gmail.com
EOF
)"
git log --oneline -1
```

Expected: a single commit at HEAD with subject `nixos/services/hermes: migrate to container mode`.

---

## Task 2: Activate via `nixos-rebuild test` and verify

**Files touched:** None — this task only activates already-committed configuration.

This task uses sudo. The user runs `nixos-rebuild test` and post-deploy verifications. If any verification fails, STOP and run the rollback path described in `2026-05-10-hermes-container-migration-design.md` §7.

- [ ] **Step 1: Re-confirm closure build (no system change)**

```bash
cd /home/chin39/shell-config && nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -3
```

Expected: build success. The closure should already be cached from Task 1 Step 6.

- [ ] **Step 2: Activate for this boot only**

```bash
cd /home/chin39/shell-config && sudo nixos-rebuild test --flake .#vm-nix 2>&1 | tail -25
```

Expected: ends with `Done. The new configuration is /nix/store/...`. Watch for:
- `Stopped Hermes Agent Gateway` (stopping the old native unit)
- `ubuntu:24.04: Pulling from library/ubuntu` (first time only, ~50 MB)
- `Creating container...` (from the module's preStart)
- `Started Hermes Agent Gateway` (the new container-mode unit)

If activation fails, **stop here**. Don't proceed to the cleanup task. The next reboot will revert to the prior generation; or you can `sudo nixos-rebuild test --flake .#vm-nix --rollback`.

- [ ] **Step 3: Verify the systemd unit is up**

```bash
systemctl status hermes-agent.service --no-pager 2>&1 | head -15
```

Expected: `Active: active (running)`. The `Main PID` line should reference `docker start` or similar (no longer the python3.12 process directly).

- [ ] **Step 4: Verify the container is actually running**

```bash
docker ps --filter name=hermes-agent --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
```

Expected: one line showing `hermes-agent | Up X seconds | ubuntu:24.04`.

- [ ] **Step 5: Verify chin39's `hermes` is the CLI router (not the real binary)**

```bash
file $(which hermes)
```

Expected: a line like `<path>: a /nix/store/.../bin/bash script, ASCII text executable` or similar — i.e., a shell script. **NOT** a `Python script` (Python entrypoint) or an ELF binary.

If `file` reports a Python script or ELF, container-mode router substitution didn't happen. Re-check Task 1 Step 5's `nix eval` confirmations.

- [ ] **Step 6: Confirm the probe ran and updated `.env`**

```bash
sg hermes -c 'grep "^LOCAL_MODEL_NAME=" /var/lib/hermes/.hermes/.env'
```

Expected: a line like `LOCAL_MODEL_NAME=Qwen3.6-27B-UD-Q4_K_XL.gguf` (or whatever GGUF the LAN llama-server is currently serving).

If you see `LOCAL_MODEL_NAME=local-unavailable`, the Windows box was unreachable at probe time — wake it up and `sudo systemctl restart hermes-agent`, then re-check.

If there's NO `LOCAL_MODEL_NAME=` line at all, the probe didn't run or didn't write — check `journalctl -u hermes-agent --since '2 min ago' | grep hermes-probe`.

- [ ] **Step 7: Smoke test — gateway responds to `hermes status`**

```bash
hermes status 2>&1 | head -25
```

Expected: gateway shown as `running`, telegram platform configured (since you previously committed the telegram tokens). No errors.

If `hermes status` hangs or errors, container routing isn't working. Check `docker logs hermes-agent` for symptoms.

- [ ] **Step 8: Smoke test — local model**

```bash
hermes -z "say ok in three words" 2>&1 | tail -5
```

Expected: a 3-word response from the local Qwen model. Latency under ~5 seconds.

If you see `Permission denied` errors here, container routing didn't take and chin39's `hermes` is still hitting the real binary as chin39 (which was the original problem). Stop and report.

- [ ] **Step 9: Smoke test — DeepSeek alias**

```bash
hermes -z "say ok in three words" --provider deepseek -m deepseek-v4-flash 2>&1 | tail -5
```

Expected: a 3-word response from DeepSeek. Latency may be 1–3 seconds depending on the LAN proxy.

- [ ] **Step 10: Decide go/no-go**

If steps 3–9 all passed: **green light** — proceed to Task 3 (state cleanup).

If anything failed: **stop**. Reboot the host (`sudo reboot`) — `nixos-rebuild test` doesn't update the boot loader, so the prior generation will come back. Diagnose with the failure evidence in hand, edit `nixos/services/hermes.nix`, re-commit, retry from Task 1 Step 7.

---

## Task 3: One-shot state cleanup

**Files touched:** Live state under `/var/lib/hermes/.hermes/`. No git changes in this task.

After the migration, several chin39-owned files remain in the gateway's state directory from earlier interactive use. We delete them now (most are auto-recreated; one is a skill we explicitly nuke).

- [ ] **Step 1: Audit chin39-owned files**

```bash
sg hermes -c 'find /var/lib/hermes/.hermes -user chin39 -printf "%M %u:%g %p\n" 2>/dev/null'
```

Expected output (or similar):
```
-rw-r--r-- chin39:hermes /var/lib/hermes/.hermes/.hermes_history
-rw-r--r-- chin39:hermes /var/lib/hermes/.hermes/.update_check
-rw-rw---- chin39:hermes /var/lib/hermes/.hermes/sessions/session_*.json   (multiple files)
-rw-r--r-- chin39:hermes /var/lib/hermes/.hermes/skills/.usage.json.lock
-rw------- chin39:hermes /var/lib/hermes/.hermes/skills/.usage.json
drwxr-sr-x chin39:hermes /var/lib/hermes/.hermes/skills/research/news-aggregation
-rw------- chin39:hermes /var/lib/hermes/.hermes/skills/research/news-aggregation/SKILL.md
-rw------- chin39:hermes /var/lib/hermes/.hermes/skills/research/news-aggregation/scripts/fetch_news.py
```

Confirm this matches roughly what's expected. If you see paths NOT in this list, document them but don't delete — flag in your report.

- [ ] **Step 2: Delete the chin39-owned cruft files**

```bash
rm -f /var/lib/hermes/.hermes/.hermes_history \
      /var/lib/hermes/.hermes/.update_check \
      /var/lib/hermes/.hermes/skills/.usage.json \
      /var/lib/hermes/.hermes/skills/.usage.json.lock \
      /var/lib/hermes/.hermes/sessions/session_*.json
```

These are owned by chin39, so chin39 can delete them without sudo. Each is auto-recreated on next gateway startup or skill curator run.

- [ ] **Step 3: Nuke the news-aggregation skill**

The `news-aggregation` skill was created during chin39's earlier interactive testing. Per the spec, we delete it entirely.

```bash
sudo rm -rf /var/lib/hermes/.hermes/skills/research/news-aggregation
sudo rmdir /var/lib/hermes/.hermes/skills/research 2>/dev/null || true
```

`sudo` is needed because `news-aggregation/` is owned by chin39 but the FILES inside have mode `0600` and `rmdir` of the parent fails if it's not empty. The `2>/dev/null || true` on the `rmdir` swallows the case where the directory is already gone.

- [ ] **Step 4: Re-audit — should now be empty**

```bash
sg hermes -c 'find /var/lib/hermes/.hermes -user chin39 2>/dev/null'
```

Expected: empty output. If any path appears, that one slipped through — report which path.

- [ ] **Step 5: Re-run smoke tests to confirm cleanup didn't break anything**

```bash
hermes status 2>&1 | head -10
hermes -z "say ok" 2>&1 | tail -3
```

Expected: gateway still healthy, model still responsive. If either fails after cleanup, the cleanup deleted something the gateway needed — restore from `/nix/store` (config) or accept the loss (sessions / history).

- [ ] **Step 6: No commit (state-only changes)**

Nothing in git was modified by this task. Skip the commit step.

---

## Task 4: Persist with `nixos-rebuild switch`

**Files touched:** None — same closure as Task 2, this just makes it survive a reboot.

- [ ] **Step 1: Persist the activation**

```bash
cd /home/chin39/shell-config && sudo nixos-rebuild switch --flake .#vm-nix 2>&1 | tail -10
```

Expected: same activation log as Task 2 Step 2, plus a "updating GRUB / systemd-boot" line (the boot loader gets the new generation).

- [ ] **Step 2: Confirm new generation is current**

```bash
readlink /nix/var/nix/profiles/system | head
```

Expected: `system-NNN-link` where `NNN` is HIGHER than the generation that was current before this migration (e.g., if the previous was 303, the new should be 304+).

- [ ] **Step 3: Confirm hermes-agent is still in the active closure**

```bash
ls -la /nix/var/nix/profiles/system/etc/systemd/system/hermes-agent.service
```

Expected: a symlink pointing into `/nix/store/<hash>-unit-hermes-agent.service/`. The unit file content (`cat` it via `sudo`) should reference `docker` somewhere (since we're now in container mode).

- [ ] **Step 4: Final verification — chin39's `hermes` workflow works without `sudo` ceremony**

```bash
hermes status 2>&1 | head -5
hermes -z "say ok if you are alive" 2>&1 | tail -3
```

Expected: both succeed. No `Permission denied`. No password prompts. No need for `sudo -u hermes` or `sg hermes`. The whole point of the migration.

- [ ] **Step 5: No commit (nothing changed in git)**

This task only persists already-committed state. Skip the commit step.

If you want a marker commit linking back to the spec/plan, optionally:

```bash
cd /home/chin39/shell-config && git commit --allow-empty -m "$(cat <<'EOF'
chore: hermes container migration activated on vm-nix

- nixos-rebuild switch completed; hermes-agent.service now runs
  hermes inside an ubuntu:24.04 container via docker
- chin39's `hermes` is the CLI router; no permission collisions
- Spec: docs/superpowers/specs/2026-05-10-hermes-container-migration-design.md
- Plan: docs/superpowers/plans/2026-05-10-hermes-container-migration-implementation.md

Signed-off-by: chinqrw@gmail.com
EOF
)"
```

(Optional, your call.)

---

## Rollback procedures

If anything goes wrong at any step, in escalating order of cost:

1. **Bad config caught at Task 1's `nix build` (Step 6)** → Fix `hermes.nix`, re-run Step 6, no system change yet. Zero residue.

2. **Bad config caught at Task 2's `nixos-rebuild test`** → `sudo reboot`. Prior generation comes back. Edit `hermes.nix`, recommit, retry from Task 1 Step 7.

3. **Bad behavior after `switch` (Task 4)** → `sudo nixos-rebuild switch --flake .#vm-nix --rollback`, or pick prior generation from systemd-boot menu. ~10 seconds.

4. **Bad commit needs to come out** → `git revert <sha>`, `nixos-rebuild switch` again. The flake is the source of truth.

5. **Container won't start** → `docker logs hermes-agent` for symptoms. Common: image pull failure (transient — retry). If the gateway crashes inside the container, `docker logs` shows the python traceback; fix in `hermes.nix` and re-`switch`.

6. **State directory got into a bad shape** → `sudo systemctl stop hermes-agent`, surgically delete the offending file in `/var/lib/hermes/.hermes/`, `sudo systemctl start hermes-agent`. Bind-mounted state survives container destroy/recreate.

---

## Self-review against spec

Cross-checking every spec section against tasks:

| Spec section | Plan coverage |
|---|---|
| §1 Why this exists | Background; not implemented (it's the rationale) |
| §2 Goal & non-goals | Goal: Tasks 1–4 collectively achieve container mode + drop patches + revise probe + state cleanup. Non-goals: explicitly absent from plan. |
| §3 Architecture | Task 1 Step 2 implements the container.* block + revised probe |
| §4 File changes (add container, replace probe, drop 4 patches) | Task 1 Step 2 (full file rewrite); Task 1 Step 5 verifies each removal landed |
| §5 State cleanup | Task 3 (delete chin39 cruft + nuke news-aggregation) |
| §6 Validation | Pre-deploy: Task 1 Steps 3–6. Post-deploy: Task 2 Steps 3–9. Permission audit: Task 3 Step 4. |
| §7 Failure modes & rollback | Captured in "Rollback procedures" above; Task 2 Step 10 + Task 3 Step 5 cover go/no-go decisions |
| §8 Implementation order | Phase 1=Task 1, Phase 2=part of Task 2 Step 1, Phase 3=Task 2, Phase 4=Task 3, Phase 5=Task 4 |
| §9 Out of scope | Explicitly NOT in plan |
| §10 Verified facts | Implicit — the design is correct because it's verified against hermes-agent source |

No gaps.

**Placeholder scan:** searched for "TBD", "TODO", "later", "appropriate", "as needed". None present.

**Type/name consistency:**
- `LOCAL_MODEL_NAME` — used identically in Task 1 (settings reference) and Task 2 (audit grep) ✓
- `OPENAI_API_KEY`, `DEEPSEEK_API_KEY` — referenced via `${VAR}` syntax everywhere ✓
- `ubuntu:24.04` — same string in Task 1 Step 2 (file content) and Task 2 Step 4 (docker ps verification) ✓
- `hermes-agent` (service name + container name) — same in all references ✓
- `deepseek-v4-flash` — only literal in `let deepseekModel = ...; in`; referenced via `deepseekModel` everywhere ✓
- `192.168.0.101:8087` — same in two settings blocks (model + model_aliases.local) and the probe script ✓

---

## Out of scope (explicit non-goals — do not implement here)

- MCP servers beyond Telegram (already configured in `secrets/hermes.env` from prior work)
- Per-platform tool restrictions (`platform_toolsets`) — separate hardening sprint
- Memory poisoning defenses, audit logging dashboards
- Wake-on-LAN for the Windows llama.cpp box
- Disk-fill protection on `/var/lib/hermes/workspace`
- Migration of `secrets/hermes.env` to a different secrets manager

These come in follow-up plans, not this one.
