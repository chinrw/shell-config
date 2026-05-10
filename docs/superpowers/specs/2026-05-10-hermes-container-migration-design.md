# Hermes Agent — Container Mode Migration

**Status:** design approved, implementation pending
**Date:** 2026-05-10
**Author:** chin39 + Claude (brainstorming retrospective)
**Target host:** `vm-nix` (192.168.0.240)
**Supersedes (operationally):** parts of `2026-05-10-hermes-service-design.md` (the host-integration patches it implies are removed by this migration)
**Related commits being undone in spirit:**
- `14b8a0c` — chin39 in hermes group
- `2eb73a8` — sudoers + tmpfiles + activation script
- `8b54737` — `.hermes_history` in fixup loop
- `f43e33f` — recursive chown sweep

## 1. Why this exists

Over the course of bringing up `services.hermes-agent` in **native mode**, four reactive permission patches accumulated. Each one fixed a different symptom of a single root cause: chin39 typing plain `hermes` invoked the real binary as themselves, polluting the gateway's state directory with chin39-owned files that the hermes user (which the gateway runs as) couldn't read.

**Root cause** — two design decisions interacting:

1. `services.hermes-agent.addToSystemPackages = true` — puts the real `hermes` binary on every user's `$PATH`
2. `environment.variables.HERMES_HOME = "/var/lib/hermes/.hermes"` — set system-wide by the same code path

Together, they made it possible for chin39's interactive shell to invoke hermes-as-chin39 against the gateway's state dir. Every chin39 invocation rewrote files there as chin39, breaking subsequent hermes-user reads.

The four patches were band-aids on the symptom. None addressed the root cause.

**Container mode does address the root cause.** When `services.hermes-agent.container.enable = true`, the binary `addToSystemPackages` installs is no longer the real hermes — it's a **CLI router** that `docker exec`s into the gateway container. Every chin39-issued command runs as the container's hermes user. Pollution becomes structurally impossible.

This spec is the migration plan from native to container mode.

## 2. Goal & non-goals

**Goal.** Move `services.hermes-agent` to `container.enable = true` on `vm-nix`. Drop the four band-aid patches because container mode subsumes them. Keep the runtime model-name probe (chin39 swaps GGUFs on the local llama.cpp server) using a revised mechanism that fits container mode.

**Non-goals (for this migration).**
- No model / settings changes — DeepSeek compression provider, local llama.cpp default, model_aliases, security.tirith_*, compression.* all carry over verbatim
- No re-design of the secrets file (sops works the same in container mode)
- No edits to `nixos/vm-nix/default.nix` — only `nixos/services/hermes.nix`
- No rollback of git history (we don't `git revert` the patches; we just remove their content in this commit and let history show the evolution)
- No multi-host scaling — single user (chin39), single host (vm-nix)
- No MCP servers wired in v1 — that comes later

## 3. Architecture

```
┌────────────────────────────── vm-nix host ───────────────────────────────────┐
│                                                                              │
│  systemd: hermes-agent.service  (manages the container lifecycle)            │
│           │                                                                  │
│           ├─ ExecStartPre: probe llama.cpp /v1/models, write                 │
│           │   LOCAL_MODEL_NAME directly into /var/lib/hermes/.hermes/.env    │
│           │                                                                  │
│           ▼ docker start -a hermes-agent                                     │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │ ubuntu:24.04 container "hermes-agent"  (persistent across reboots) │    │
│   │                                                                    │    │
│   │  Bind mounts:                                                      │    │
│   │    /nix/store        ← host /nix/store (ro)                        │    │
│   │    /data             ← host /var/lib/hermes (rw)                   │    │
│   │    /home/hermes      ← host /var/lib/hermes/home (rw)              │    │
│   │                                                                    │    │
│   │  Inside the container:                                             │    │
│   │    user: hermes (UID matches host hermes)                          │    │
│   │    PATH: /data/current-package/bin (the nix-built hermes)          │    │
│   │    ENV:  HERMES_HOME=/data/.hermes  (= host /var/lib/hermes/.hermes)│    │
│   │    process: hermes gateway run --replace                           │    │
│   │    reads .env at every gateway startup via load_hermes_dotenv()    │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  chin39's PATH:  /run/current-system/sw/bin/hermes                           │
│       (CLI router from addToSystemPackages — execs                           │
│        `docker exec -i hermes-agent --user hermes -- hermes "$@"`)           │
│                                                                              │
└──────────┬──────────────────────────────────────┬────────────────────────────┘
           │                                      │
           │ HTTP (LAN, no proxy)                 │ HTTPS via 192.168.0.240:10809
           ▼                                      ▼
   192.168.0.101:8087                  api.deepseek.com/v1
   llama.cpp                           DeepSeek (compression + alias)
```

### Key invariants

1. **chin39 cannot write to `/var/lib/hermes/.hermes/` as themselves.** The `hermes` binary on chin39's PATH is the router; every command goes through `docker exec --user hermes`. All writes are by the container's hermes user, which maps to the host's hermes user via UID.

2. **State is preserved across container restarts and image upgrades.** `/var/lib/hermes` is bind-mounted as `/data` — the container's filesystem changes don't touch it. Only the container's writable layer (`/usr`, `/usr/local`, `/tmp`) is volatile.

3. **Sops + secret merging unchanged.** The activation script writes `/var/lib/hermes/.hermes/.env` from `cfg.environmentFiles + cfg.environment` at every `nixos-rebuild`. The container reads that file via the bind mount.

4. **Runtime probe writes to the same `.env` file at every service start.** `ExecStartPre` runs on the host, idempotently replaces the `LOCAL_MODEL_NAME=` line in `/var/lib/hermes/.hermes/.env`. Self-healing across nixos-rebuilds (which would otherwise wipe the probe's contribution during the activation re-merge).

## 4. File changes

Single edit: `nixos/services/hermes.nix`. Net diff is ~80 lines smaller.

### Add — the container block

Inside `services.hermes-agent`:

```nix
container = {
  enable     = true;
  backend    = "docker";
  image      = "ubuntu:24.04";
  hostUsers  = [ "chin39" ];
};
```

`addToSystemPackages = true` stays; combined with `container.enable = true`, the module installs the CLI router (not the real binary) on system PATH. `hostUsers = [ "chin39" ]` creates the symlink `/home/chin39/.hermes → /var/lib/hermes/.hermes` so chin39's view aligns with the gateway's state.

### Replace — the runtime probe

Old (the old `/run/hermes/discovered.env` indirection that only worked at activation time):

```nix
systemd.services.hermes-agent = {
  serviceConfig.RuntimeDirectory = "hermes";
  serviceConfig.RuntimeDirectoryMode = "0750";
  serviceConfig.ExecStartPre = [
    (pkgs.writeShellScript "hermes-probe-local-model" ''
      ...writes /run/hermes/discovered.env...
    '')
  ];
};

services.hermes-agent.environmentFiles = [
  config.sops.secrets."hermes-env".path
  "/run/hermes/discovered.env"
];
```

New (direct edit of the merged `.env` file at every service start):

```nix
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

services.hermes-agent.environmentFiles = [
  config.sops.secrets."hermes-env".path
  # /run/hermes/discovered.env entry removed — probe writes .env directly
];
```

Properties of the new mechanism:
- ExecStartPre runs as root (in container mode the systemd unit needs root to invoke `docker run`). Root can write `.env` regardless of its mode/owner.
- The probe is idempotent (`sed -i` removes the existing line before appending the new one). Multiple restarts in a row produce identical results.
- Activation overwrites `.env` at every `nixos-rebuild`; the next service start re-runs the probe and re-adds `LOCAL_MODEL_NAME=`. Self-healing.
- Container reads `.env` via bind mount on its own startup. No `extraVolumes` needed.

### Remove — the four host-integration patches

| Block | Why we drop it |
|---|---|
| `users.users.chin39.extraGroups = [ "hermes" ];` | chin39 no longer reads `/var/lib/hermes` directly; the CLI router goes through `docker exec` |
| `security.sudo.extraRules` (passwordless `sudo -u hermes hermes`) | Not needed; chin39's `hermes` is the router, never the real binary |
| `systemd.tmpfiles.rules` for `cron/` tree | The container's hermes user manages its own filesystem; no host-side group access needed |
| `system.activationScripts.hermesStatePerms` (chown sweep) | Source of pollution gone; sweep finds nothing |

### Settings — unchanged values, but `model.default` keeps the substitution

```nix
settings = {
  model = {
    default = "\${LOCAL_MODEL_NAME}";    # resolved from .env at gateway startup
    provider = "custom";
    base_url = "http://192.168.0.101:8087/v1";
    api_key = "\${OPENAI_API_KEY}";
  };

  auxiliary.compression = {
    provider = "deepseek";
    model = deepseekModel;                # = "deepseek-v4-flash"
    timeout = 30;
  };

  compression = {
    enabled = true;
    threshold = 0.50;
    target_ratio = 0.20;
    protect_last_n = 20;
  };

  model_aliases = {
    deepseek = { model = deepseekModel; provider = "deepseek"; };
    local = {
      model = "\${LOCAL_MODEL_NAME}";
      provider = "custom";
      base_url = "http://192.168.0.101:8087/v1";
    };
  };

  terminal = {
    backend = "local";    # the container IS the boundary — no nested docker
    cwd = ".";
    timeout = 180;
  };

  security = {
    tirith_enabled = true;
    tirith_fail_open = false;
  };
};
```

`extraPackages` stays as-is (matches the upstream dev shell's tool list); `extraPythonPackages = [ ];` stays as-is (the sealed venv provides what hermes needs).

## 5. State cleanup

The existing `/var/lib/hermes/.hermes/` contains chin39-owned cruft from earlier interactive use. Container mode prevents new pollution but doesn't clean up legacy files. One-shot manual cleanup after the migration commit:

```bash
# Files chin39 owns — chin39 deletes without sudo
rm -f /var/lib/hermes/.hermes/.hermes_history \
      /var/lib/hermes/.hermes/.update_check \
      /var/lib/hermes/.hermes/skills/.usage.json \
      /var/lib/hermes/.hermes/skills/.usage.json.lock \
      /var/lib/hermes/.hermes/sessions/session_*.json

# Nuke the news-aggregation skill (per chin39's instruction)
rm -rf /var/lib/hermes/.hermes/skills/research/news-aggregation
rmdir /var/lib/hermes/.hermes/skills/research 2>/dev/null || true
```

After this:

```bash
sg hermes -c 'find /var/lib/hermes/.hermes -user chin39' | head
# expect: empty
```

## 6. Validation

### Pre-deploy (no privileged commands)

```bash
cd /home/chin39/shell-config

# Module evaluates with new container config
nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.enable
# expect: true

nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.image --raw
# expect: ubuntu:24.04

nix eval .#nixosConfigurations.vm-nix.config.services.hermes-agent.container.hostUsers --json
# expect: ["chin39"]

# Confirm patches gone
nix eval .#nixosConfigurations.vm-nix.config.users.users.chin39.extraGroups --json | jq 'index("hermes")'
# expect: null

# Full closure rebuild
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -5
# expect: build success
```

### Activation with `test` before `switch`

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

Watch journal for: probe output, container creation, `Started Hermes Agent Gateway`, no errors.

### Post-deploy verification

```bash
docker ps --filter name=hermes-agent
# expect: container Up, image ubuntu:24.04

file $(which hermes)
# expect: a shell script (the CLI router), NOT an ELF binary

hermes status                                                    # gateway healthy
hermes -z "say ok"                                               # local model smoke test
hermes -z "say ok" --provider deepseek -m deepseek-v4-flash      # DeepSeek smoke test
```

### Permission audit

```bash
sg hermes -c 'find /var/lib/hermes/.hermes -user chin39 2>/dev/null' | head
# expect: empty (after Phase 4 cleanup)

stat /var/lib/hermes/.hermes/config.yaml | grep -E "Uid|Gid|Access"
# expect: Uid hermes / Gid hermes / mode 0640
```

After running a few `hermes -z` invocations, re-check — `find -user chin39` should still return empty, proving the structural fix.

## 7. Failure modes & rollback

| Failure | Symptom | Action |
|---|---|---|
| `ubuntu:24.04` image pull fails | container won't start; journal shows pull error | check internet from vm-nix, retry |
| Docker daemon issue | dependent service errors | `sudo systemctl start docker` |
| Old service didn't stop cleanly | port conflict / overlapping Telegram poll | `sudo systemctl stop hermes-agent` then re-`switch` |
| Container starts but gateway crashes | `docker ps` up, `hermes status` reports gateway down | `docker logs hermes-agent` — likely a settings-key issue; fix and re-`switch` |
| chin39's `hermes` resolves to ELF binary | `addToSystemPackages` cache stale | open a fresh shell or re-login |
| Probe failure doesn't update LOCAL_MODEL_NAME | `cat /var/lib/hermes/.hermes/.env | grep LOCAL_MODEL_NAME` shows stale value | systemctl restart hermes-agent (probe re-runs); check journal for `[hermes-probe]` line |

### Rollback paths

1. **Bad config caught at `nixos-rebuild test`** → `sudo reboot`. Zero residue.
2. **Bad config after `switch`** → `sudo nixos-rebuild switch --flake .#vm-nix --rollback`, or pick prior generation from systemd-boot. ~10 s.
3. **Bad commit needs to come out** → `git revert <sha>`, `nixos-rebuild switch` again. The flake is the source of truth.
4. **State directory corrupted** → `sudo systemctl stop hermes-agent`, surgically delete the offending file in `/var/lib/hermes/.hermes/`, restart. Bind-mounted state survives container destroy.

## 8. Implementation order

1. Edit `nixos/services/hermes.nix` per §4
2. Pre-deploy validation per §6
3. Single commit with the message in §5 of the brainstorm transcript (paraphrased: "migrate to container mode; drop host-integration patches; revise probe to direct `.env` edit")
4. `sudo nixos-rebuild test --flake .#vm-nix` — activate container mode; run post-deploy verification
5. State cleanup per §5 (delete chin39 cruft + nuke `news-aggregation`)
6. Re-audit; re-run smoke tests
7. `sudo nixos-rebuild switch --flake .#vm-nix` — persist
8. Final journal check; tell chin39 they can `git push` when ready

## 9. Out of scope (explicit non-goals)

- MCP server wiring (Telegram is already configured; everything else deferred)
- Per-platform tool restrictions (`platform_toolsets`) — the brainstorm covered this as a separate hardening sprint, not part of this migration
- Memory poisoning defenses, audit logging dashboards
- Wake-on-LAN for the Windows llama.cpp box
- Migration from sops to another secrets manager
- Disk-fill protection on `/var/lib/hermes/workspace`

## 10. Verified facts

This design has been validated against the hermes-agent source code at revision `44cdf555a83c1d8d605d095442e11efd58089533`:

| Claim | Source |
|---|---|
| `container.enable` flips between native and container service | `nix/nixosModules.nix:540, 851, 875` (the `lib.mkIf (!cfg.container.enable)` and `lib.mkIf cfg.container.enable` pair) |
| `addToSystemPackages = true` + `container.enable = true` installs the CLI router on system PATH (not the real binary) | `nix/nixosModules.nix:628`, plus the routing wrapper in `hermes_cli` (CLI Container Routing Retry Behavior) |
| Bind mounts: `/var/lib/hermes → /data`, `/var/lib/hermes/home → /home/hermes`, `/nix/store → /nix/store (ro)` | `nix/nixosModules.nix:944-946` (the `--volume` args) |
| `environmentFiles` are merged into `$HERMES_HOME/.env` at activation, not at runtime | `nix/nixosModules.nix:802-816` and 864 (comment: "no systemd EnvironmentFile needed") |
| The gateway reads `.env` at every Python startup via `load_hermes_dotenv()` | `nix/nixosModules.nix:864`, plus `hermes_cli/env_loader.py:157` |
| `hostUsers` (in container mode only) creates the `~/.hermes → ${stateDir}/.hermes` symlink for listed users | hermes nix-setup docs §4 + module source `nix/nixosModules.nix:566-572` |
| `provider: "deepseek"` is a built-in named provider with `inference_base_url=https://api.deepseek.com/v1` and `DEEPSEEK_API_KEY` | `hermes_cli/auth.py:309-316` (unchanged from the native-mode design) |
| `deepseek-v4-flash` has 1M context window | `agent/model_metadata.py:187` |
| State persists across container destroy/recreate; only writable layer is volatile | hermes nix-setup docs §4 |

Keys NOT in the schema (and not used in this design): `model.aliases.<name>`, `approvals.{mode, timeout}` — both confirmed absent in the earlier brainstorm; this spec inherits those decisions.
