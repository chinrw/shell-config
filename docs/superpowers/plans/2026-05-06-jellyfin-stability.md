# Jellyfin Stability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land all 8 stability fixes from the 2026-05-06 design spec onto the `vm-nix` NixOS host without expanding scope.

**Architecture:** Five sequential commits, each touching `nixos/vm-nix/container/jellyfin.nix` and/or `nixos/vm-nix/default.nix`. Each commit is independently verifiable via `nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link` (eval) and `nixos-rebuild test --flake .#vm-nix` (deploy). No new files. The `compose2nix`-generated structure is preserved; the local Dockerfile build path is removed.

**Tech Stack:** NixOS 24.11+, systemd, Docker (`virtualisation.oci-containers`), upstream `jellyfin/jellyfin:10.10.7` image, `pkgs.symlinkJoin` of `noto-fonts-cjk-{sans,serif}`, bash builtin TCP probe for Docker `HEALTHCHECK`.

**Spec:** `docs/superpowers/specs/2026-05-06-jellyfin-stability-design.md` (commit `7cb29d5`).

**Target host:** `vm-nix` (`192.168.0.240`). Run `nixos-rebuild` either on that host directly, or remotely with `--target-host vm-nix --use-remote-sudo` from a workstation that has SSH access.

**Per-commit completion protocol:** This repo's user CLAUDE.md mandates that after any non-trivial change, the implementer runs `nix flake check`, then delegates to the `task-verifier` subagent with a one-line summary. Apply this after each commit below.

---

## File Structure

| Path | Responsibility | Touched in |
|---|---|---|
| `nixos/vm-nix/container/jellyfin.nix` | Container, systemd dep wiring, sentinel oneshot, image pin, ports, healthcheck, restart cooldown, prune flags | Tasks 1, 2, 3, 4, 5 |
| `nixos/vm-nix/default.nix` | Firewall TCP/UDP allowlists, user lingering | Tasks 1, 3 |
| `docs/superpowers/specs/2026-05-06-jellyfin-stability-design.md` | Spec (already committed) | none |

No new files. The orphan `/home/chin39/Documents/container/jellyfin/build/Dockerfile` is left in place per spec "Out of Scope".

---

## Task 1: Fix UDP port mappings (#6)

Move `7359` and `1900` from TCP to UDP in both the container port mapping and the host firewall. `8096/tcp` (web UI) is unchanged.

**Files:**
- Modify: `nixos/vm-nix/container/jellyfin.nix:35-39`
- Modify: `nixos/vm-nix/default.nix:77-117`

- [ ] **Step 1: Edit container port mappings**

In `nixos/vm-nix/container/jellyfin.nix`, replace:

```nix
    ports = [
      "8096:8096/tcp"
      "7359:7359/tcp"
      "1900:1900/tcp"
    ];
```

with:

```nix
    ports = [
      "8096:8096/tcp"
      "7359:7359/udp"
      "1900:1900/udp"
    ];
```

- [ ] **Step 2: Edit firewall TCP allowlist**

In `nixos/vm-nix/default.nix`, find the `allowedTCPPorts` list (line 77+). Remove the bare `7359` and `1900` entries (currently on lines 98–99). The block must still contain `8096 # jellyfin`.

After edit, the relevant block reads:

```nix
    allowedTCPPorts = [

      # Alist firewall port
      5244
      5246
      5432

      5000 # local binary cache
      5001 # test webserver1
      5002 # test webserver2
      3001 # lanraragi
      7892 # AutoBangumi

      7861 # gcli2api
      8000
      8484 # clewdr claude reverse
      8888 # kik

      8765 # local python testing web
      8787
      8096 # jellyfin

      10808
      10809
      22267 # alas

      8384 # syncthing web GUI
      22000 # syncthing sync protocol
    ];
```

- [ ] **Step 3: Edit firewall UDP allowlist**

In the same file, modify `allowedUDPPorts` to add `7359` and `1900`:

```nix
    allowedUDPPorts = [
      53
      22000 # syncthing QUIC sync
      21027 # syncthing local discovery
      7359 # jellyfin client autodiscovery
      1900 # SSDP / DLNA
    ];
```

- [ ] **Step 4: Eval-check the configuration**

Run from the repo root:

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -20
```

Expected: build succeeds with no output to stderr (or only download/cache messages). If there are evaluation errors, fix them before continuing.

- [ ] **Step 5: Apply to vm-nix**

On the vm-nix host (or via remote):

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

Expected: rebuild completes; `iptables -L -n` shows the new TCP/UDP rules. The container **will recreate** because port mappings (including protocol) are part of the container spec — `virtualisation.oci-containers` triggers `docker rm` + `docker run` whenever they change. Brief outage (~5 seconds) on this step.

- [ ] **Step 6: Verify autodiscovery**

From a phone/laptop on the LAN running the Jellyfin client app, trigger "Find servers" or restart the app. Expected: vm-nix is found via UDP autodiscovery (port `7359/udp`).

For SSDP (`1900/udp`): on a Linux host on the same LAN, run:

```bash
gssdp-discover -i <lan-iface> -t urn:schemas-upnp-org:device:MediaServer:1 2>&1 | head -20
```

Expected: Jellyfin announces itself. (If `gssdp-discover` is unavailable, this step is best-effort; the Jellyfin client check above is the primary signal.)

- [ ] **Step 7: Commit**

```bash
git add nixos/vm-nix/container/jellyfin.nix nixos/vm-nix/default.nix
git commit -m "$(cat <<'EOF'
fix(jellyfin): expose autodiscovery and SSDP as udp

- container port mappings 7359 and 1900 changed from tcp to udp
- firewall allowedTCPPorts no longer lists 7359 / 1900
- firewall allowedUDPPorts gains 7359 (jellyfin autodiscovery) and 1900 (SSDP)
- 8096/tcp web ui unchanged
- spec issue #6: lan auto-discovery silently failed because both protocols are udp

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 2: Scope `autoPrune` to keep recent images (#8)

Replace `virtualisation.docker.autoPrune.enable = true;` with a structured config that filters out images created in the last 30 days, so the pinned upstream image (Task 4) is never pruned during a brief outage.

**Files:**
- Modify: `nixos/vm-nix/container/jellyfin.nix:11-16`

- [ ] **Step 1: Edit the docker block**

Replace:

```nix
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
```

with:

```nix
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" "--filter" "until=720h" ];
    };
  };
```

- [ ] **Step 2: Eval-check**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Apply**

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

- [ ] **Step 4: Verify the prune timer/service**

```bash
systemctl cat docker-prune.service | grep ExecStart
```

Expected output contains:

```
ExecStart=/run/current-system/sw/bin/docker system prune -f --all --filter until=720h
```

- [ ] **Step 5: Verify pruning would skip recent images (dry-run)**

```bash
docker system prune --all --filter until=720h --dry-run 2>&1 | head -30
```

Expected: the currently-running Jellyfin image (today: `compose2nix/jellyfin`; after Task 4: `jellyfin/jellyfin:10.10.7`) is not in the would-prune list. Recent images are skipped.

- [ ] **Step 6: Commit**

```bash
git add nixos/vm-nix/container/jellyfin.nix
git commit -m "$(cat <<'EOF'
fix(jellyfin): scope docker autoprune with until=720h filter

- weekly autoprune now restricted to objects older than 30 days
- protects the pinned jellyfin image from being pruned during a brief container outage
- spec issue #8: previously enabled with no filter, risk of forced rebuilds after transient stops

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 3: Mount sentinel + dep rewiring + delay timer removal + user lingering (#1, #2, #7)

Single bundled commit because the pieces are tightly coupled. Adds the sentinel oneshot, fixes `Requires=`/`After=`, removes the broken `home-chin39-mounts-*.mount` references, removes the stale `/mnt/autofs/data` reference, deletes both delay timers, makes the root target start at boot, and enables user lingering for `chin39`.

**Files:**
- Modify: `nixos/vm-nix/container/jellyfin.nix` (multiple sections)
- Modify: `nixos/vm-nix/default.nix` (insert one line in the `users.users.chin39` block)

- [ ] **Step 1: Enable user lingering for chin39**

In `nixos/vm-nix/default.nix`, find the `users.users.chin39` block (line 37). Add `linger = true;` as a top-level field:

```nix
  users.users.chin39 = {
    isNormalUser = true;
    description = "chin39";
    linger = true;
    extraGroups = [
      "networkmanager"
      "docker"
      "wheel"
      "aria2"
      "media"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = [ config.sops.secrets.ssh_pub_key.path ];
  };
```

If the eval check in Step 6 fails with `error: The option 'users.users.chin39.linger' does not exist`, the running NixOS version predates that option; replace the line with `tmpfiles` rules at the module top level:

```nix
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/chin39 0644 root root - -"
  ];
```

(Place the `systemd.tmpfiles.rules` block alongside the other top-level attributes — for example, just before `boot.loader.systemd-boot.enable`.)

- [ ] **Step 2: Remove the `jellyfinMounts` let-binding**

In `nixos/vm-nix/container/jellyfin.nix`, the file currently begins:

```nix
# Auto-generated using compose2nix v0.3.2-pre.
{ pkgs, lib, ... }:
let
  jellyfinMounts = [
    "home-chin39-mounts-alist.mount"
    "home-chin39-mounts-115\\x2dsingle.mount"
    "home-chin39-mounts-union\\x2d115.mount"
  ];
in
{
```

Replace those nine lines with:

```nix
# Auto-generated using compose2nix v0.3.2-pre, then edited.
{ pkgs, lib, ... }:
{
```

- [ ] **Step 3: Add the mount sentinel service**

In `nixos/vm-nix/container/jellyfin.nix`, immediately before `systemd.services."docker-jellyfin"` (currently line 46), insert:

```nix
  systemd.services."jellyfin-mount-ready" = {
    description = "Wait for user-scope rclone FUSE mounts to be ready";
    path = [ pkgs.coreutils pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "180";
    };
    script = ''
      set -eu
      deadline=$(( $(date +%s) + 120 ))
      for m in /home/chin39/mounts/{alist,115-single,union-115}; do
        while ! ( mountpoint -q "$m" \
                  && [ -n "$(ls -A "$m" 2>/dev/null | head -n1)" ] ); do
          if [ "$(date +%s)" -gt "$deadline" ]; then
            echo "timeout waiting for $m" >&2
            exit 1
          fi
          sleep 2
        done
      done
    '';
  };

```

- [ ] **Step 4: Rewire `docker-jellyfin.service`**

Replace the entire `systemd.services."docker-jellyfin"` block (currently lines 46–67) with:

```nix
  systemd.services."docker-jellyfin" = {
    unitConfig = {
      RequiresMountsFor = [ "/mnt/data/video/jellyfin" ];
      StartLimitIntervalSec = "10min";
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Restart = lib.mkOverride 90 "on-failure";
      RestartSec = "10s";
    };
    after = [
      "docker-network-jellyfin_default.service"
      "jellyfin-mount-ready.service"
      "mnt-data.mount"
    ];
    requires = [
      "docker-network-jellyfin_default.service"
      "jellyfin-mount-ready.service"
      "mnt-data.mount"
    ];
    partOf = [ "docker-compose-jellyfin-root.target" ];
  };
```

Net change vs. existing: `bindsTo = jellyfinMounts;` is gone; the broken `home-chin39-mounts-*.mount` and `docker-build-jellyfin.service` references are gone; `RequiresMountsFor=/mnt/autofs/data` is replaced with `/mnt/data/video/jellyfin`; `RestartSec`/`StartLimitIntervalSec`/`StartLimitBurst` are added.

- [ ] **Step 5: Delete the two delay timers**

Remove the entire `systemd.timers."docker-jellyfin-delay"` block (currently lines 69–75) and the entire `systemd.timers."start-jellyfin-stack-delay"` block (currently lines 123–129).

- [ ] **Step 6: Make the root target activate at boot**

Replace the existing `systemd.targets."docker-compose-jellyfin-root"` block (currently lines 117–121) with:

```nix
  systemd.targets."docker-compose-jellyfin-root" = {
    unitConfig.Description = "Root target generated by compose2nix.";
    wantedBy = [ "multi-user.target" ];
  };
```

- [ ] **Step 7: Eval-check**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -20
```

Expected: build succeeds. If the `linger` option does not exist on the running NixOS, follow the fallback in Step 1 and re-run.

- [ ] **Step 8: Apply**

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

Expected: rebuild completes. Container may or may not recreate (this set of changes does not modify `image`, `volumes`, `ports`, or `extraOptions` — Docker may keep the same container). Systemd reloads new unit definitions.

- [ ] **Step 9: Verify lingering enabled**

```bash
loginctl show-user chin39 | grep Linger
```

Expected:

```
Linger=yes
```

If still `Linger=no`, manually run `sudo loginctl enable-linger chin39` once to flip it for the running session; subsequent boots will pick it up from the Nix activation.

- [ ] **Step 10: Verify the sentinel works**

```bash
systemctl status jellyfin-mount-ready
```

Expected: `Active: active (exited)`, with the script having run and exited 0.

Force a negative test (the sentinel must time out and block jellyfin):

```bash
systemctl --user stop rclone-115-single.service
sudo systemctl restart docker-jellyfin
sleep 5
sudo systemctl status jellyfin-mount-ready --no-pager | head -20
```

Expected: `jellyfin-mount-ready` is `activating (start)` and stays so for ~120s, then fails with `timeout waiting for /home/chin39/mounts/115-single`. `docker-jellyfin` is queued behind it (state `inactive (dead)` because requirement failed).

Restore:

```bash
systemctl --user start rclone-115-single.service
sleep 10
sudo systemctl restart docker-jellyfin
```

`docker-jellyfin` should now reach `active (running)`.

- [ ] **Step 11: Verify the new dependency chain**

```bash
systemd-analyze critical-chain docker-jellyfin.service 2>&1 | head -30
```

Expected: chain includes `mnt-data.mount` and `jellyfin-mount-ready.service`, does **not** include `home-chin39-mounts-*.mount` or the deleted timers.

- [ ] **Step 12: Verify boot startup activation**

Reboot the VM (note: this affects users of the service):

```bash
sudo systemctl reboot
```

Wait ~3–4 minutes, then SSH back in and run:

```bash
systemctl status docker-compose-jellyfin-root.target --no-pager | head -10
systemctl status jellyfin-mount-ready --no-pager | head -5
systemctl status docker-jellyfin --no-pager | head -10
```

Expected: all three are `active`, and there is **no** 2-minute boot delay before activation (the wall-clock between `multi-user.target` reaching active and `docker-jellyfin` starting should be only as long as rclone + sentinel take, typically under 30 seconds with a warm cache).

- [ ] **Step 13: Commit**

```bash
git add nixos/vm-nix/container/jellyfin.nix nixos/vm-nix/default.nix
git commit -m "$(cat <<'EOF'
fix(jellyfin): wire mount sentinel and remove broken dependencies

- new system-scope jellyfin-mount-ready oneshot polls /home/chin39/mounts/{alist,115-single,union-115}
  for both mountpoint -q and non-empty ls, with a 120s deadline
- docker-jellyfin now Requires/After mnt-data.mount and jellyfin-mount-ready, drops the broken
  home-chin39-mounts-*.mount references that pointed at user-scope units
- RequiresMountsFor switched from /mnt/autofs/data (stale) to /mnt/data/video/jellyfin (actual)
- BindsTo intentionally omitted to tolerate brief CIFS blips at runtime (spec R1)
- restart cooldown added: RestartSec=10s, StartLimitIntervalSec=10min, StartLimitBurst=5
- both delay timers deleted; root target now wantedBy multi-user.target so boot ordering is by
  correctness (sentinel + mount) instead of fixed-time wait
- users.users.chin39.linger = true so user-scope rclone services start at boot without a session,
  letting the sentinel actually find the FUSE mounts present
- spec issues #1, #2, #7

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 4: Pin upstream image, drop local Dockerfile, bind Nix-managed CJK fonts (#3)

Replace the locally-built `compose2nix/jellyfin` image with `jellyfin/jellyfin:10.10.7`. CJK fonts come from a `pkgs.symlinkJoin` of `noto-fonts-cjk-sans` + `noto-fonts-cjk-serif`, bound read-only at `/config/fonts`. The `docker-build-jellyfin.service` is removed.

**Files:**
- Modify: `nixos/vm-nix/container/jellyfin.nix` (top of file, container block, build service)

- [ ] **Step 1: Add the `let` binding for CJK fonts**

In `nixos/vm-nix/container/jellyfin.nix`, the file currently begins (after Task 3):

```nix
# Auto-generated using compose2nix v0.3.2-pre, then edited.
{ pkgs, lib, ... }:
{
```

Replace with:

```nix
# Auto-generated using compose2nix v0.3.2-pre, then edited.
{ pkgs, lib, ... }:
let
  jellyfinCjkFonts = pkgs.symlinkJoin {
    name = "jellyfin-cjk-fonts";
    paths = [
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-cjk-serif
    ];
  };
in
{
```

- [ ] **Step 2: Pin the image and replace the fonts volume**

In the same file, replace the container block's `image = "compose2nix/jellyfin";` line with:

```nix
    image = "jellyfin/jellyfin:10.10.7";
```

In the same `volumes` list, replace:

```nix
      "/home/chin39/Documents/container/jellyfin/fonts:/config/fonts:rw"
```

with:

```nix
      "${jellyfinCjkFonts}/share/fonts/opentype/noto-cjk:/config/fonts:ro"
```

The complete `volumes` list after edit:

```nix
    volumes = [
      "/home/chin39/Documents/container/jellyfin/cache:/cache:rw"
      "/home/chin39/Documents/container/jellyfin/config-jellyfin:/config:rw"
      "${jellyfinCjkFonts}/share/fonts/opentype/noto-cjk:/config/fonts:ro"
      "/home/chin39/mounts:/mounts:rw"
      "/mnt/data/video/jellyfin:/jellyfin-media:rw"
    ];
```

- [ ] **Step 3: Remove `docker-build-jellyfin.service`**

In the same file, delete the entire `# Builds` comment and the following `systemd.services."docker-build-jellyfin"` block (currently spans the `# Builds` comment through the trailing `};`). After Task 3 this block is the only remaining "builds" content. Remove it cleanly so no dangling comment is left.

- [ ] **Step 4: Eval-check**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -20
```

Expected: build succeeds. If `pkgs.noto-fonts-cjk-sans` is not present (renamed in some nixpkgs revisions), substitute `pkgs.noto-fonts-cjk` (the older umbrella package) and document in the commit.

- [ ] **Step 5: Apply (will pull the new image and recreate the container)**

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

Expected: Docker pulls `jellyfin/jellyfin:10.10.7` (this needs the proxy to be reachable; the host's `http_proxy=http://192.168.0.240:10809` is already set). Container is recreated.

- [ ] **Step 6: Verify image pin**

```bash
docker inspect jellyfin --format '{{.Config.Image}}'
docker images | grep -E 'jellyfin|compose2nix'
```

Expected: first command returns `jellyfin/jellyfin:10.10.7`. Second command shows `jellyfin/jellyfin   10.10.7   ...`. The old `compose2nix/jellyfin` image likely remains in the local registry; the Task 2 prune filter will only collect it once it ages past 30 days. To remove it immediately:

```bash
docker rmi compose2nix/jellyfin
```

(Safe once `docker inspect jellyfin --format '{{.Config.Image}}'` confirms the running container is on the pinned upstream image.)

- [ ] **Step 7: Verify CJK font availability inside the container**

```bash
docker exec jellyfin ls /config/fonts | head -10
```

Expected: a list of `.ttc` files such as `NotoSansCJK-Regular.ttc`, `NotoSerifCJK-Regular.ttc`. Files must not be empty (`docker exec jellyfin stat /config/fonts/NotoSansCJK-Regular.ttc` shows non-zero size).

- [ ] **Step 8: Verify CJK subtitle rendering**

In the Jellyfin web UI, open a title that uses burned-in CJK subtitles or has CJK subtitle tracks. Play it. Observe that CJK glyphs render as proper characters, not boxes. (If you do not have such a title, this step is best-effort; the previous step is the structural guarantee.)

- [ ] **Step 9: Commit**

```bash
git add nixos/vm-nix/container/jellyfin.nix
git commit -m "$(cat <<'EOF'
fix(jellyfin): pin upstream image and drop local dockerfile

- image switched from local compose2nix/jellyfin to jellyfin/jellyfin:10.10.7
- docker-build-jellyfin.service removed; the local Dockerfile is no longer consumed
- CJK fonts now provided via symlinkJoin of noto-fonts-cjk-sans and noto-fonts-cjk-serif,
  bound read-only at /config/fonts
- prior /home/chin39/Documents/container/jellyfin/fonts host bind removed
- removes proxy-dependent apt-install step at container build time
- spec issue #3

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 5: HEALTHCHECK + restart cooldown verification (#4)

Adds Docker `HEALTHCHECK` flags to the container `extraOptions`. The systemd-side restart cooldown was already added in Task 3; this task verifies it end-to-end with a forced failure.

**Files:**
- Modify: `nixos/vm-nix/container/jellyfin.nix` (container `extraOptions`)

- [ ] **Step 1: Add healthcheck flags**

In `nixos/vm-nix/container/jellyfin.nix`, replace the `extraOptions` list:

```nix
    extraOptions = [
      "--network-alias=jellyfin"
      "--network=jellyfin_default"
    ];
```

with:

```nix
    extraOptions = [
      "--network-alias=jellyfin"
      "--network=jellyfin_default"
      "--health-cmd=bash -c '</dev/tcp/127.0.0.1/8096'"
      "--health-interval=30s"
      "--health-timeout=5s"
      "--health-retries=3"
      "--health-start-period=60s"
    ];
```

- [ ] **Step 2: Eval-check**

```bash
nix build .#nixosConfigurations.vm-nix.config.system.build.toplevel --no-link 2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Apply (recreates the container because extraOptions changed)**

```bash
sudo nixos-rebuild test --flake .#vm-nix
```

- [ ] **Step 4: Verify healthcheck reports healthy**

Wait at least 90 seconds for the start-period to elapse, then:

```bash
docker inspect jellyfin --format '{{.State.Health.Status}}'
```

Expected: `healthy`.

If it reports `unhealthy`, run the probe manually to debug:

```bash
docker exec jellyfin bash -c '</dev/tcp/127.0.0.1/8096' && echo OK
```

If that fails, the listener inside the container is not responding on `127.0.0.1:8096`; check `docker logs jellyfin` for startup errors. Otherwise the bash builtin probe is fine.

- [ ] **Step 5: Verify healthcheck flags transitions to unhealthy**

```bash
docker pause jellyfin
sleep 130   # >= 3 retries * 30s interval + 5s timeout
docker inspect jellyfin --format '{{.State.Health.Status}}'
```

Expected: `unhealthy`.

Restore:

```bash
docker unpause jellyfin
sleep 60
docker inspect jellyfin --format '{{.State.Health.Status}}'
```

Expected: back to `healthy`.

- [ ] **Step 6: Verify restart cooldown is in effect**

```bash
systemctl show docker-jellyfin -p RestartUSec -p StartLimitIntervalUSec -p StartLimitBurst
```

Expected output:

```
RestartUSec=10s
StartLimitIntervalUSec=10min
StartLimitBurst=5
```

(Property names use the systemd-internal `*USec` form.)

- [ ] **Step 7: Force restart-cooldown rate-limit (optional but recommended)**

This step proves the cooldown bounds a flap. It will leave the unit in a `failed` state until you run the recovery commands below.

```bash
# Make the container start fail by introducing a bad volume bind:
sudo systemctl stop mnt-data.automount mnt-data.mount
sudo umount /mnt/data 2>/dev/null || true
sudo mv /mnt/data /mnt/data.disabled
for i in 1 2 3 4 5 6; do
  sudo systemctl restart docker-jellyfin || true
  sleep 2
done
sudo journalctl -u docker-jellyfin -n 50 --no-pager | grep -i 'start request\|rate limit\|failed'
```

Expected: in the journal, you see at most 5 start attempts within 10 minutes, then a "Start request repeated too quickly" / rate-limit message.

Restore:

```bash
sudo mv /mnt/data.disabled /mnt/data
sudo systemctl start mnt-data.automount
sudo systemctl reset-failed docker-jellyfin
sudo systemctl restart docker-jellyfin
sleep 30
docker inspect jellyfin --format '{{.State.Health.Status}}'
```

Expected: container back to `healthy`.

- [ ] **Step 8: Commit**

```bash
git add nixos/vm-nix/container/jellyfin.nix
git commit -m "$(cat <<'EOF'
fix(jellyfin): add healthcheck and verify restart cooldown

- docker healthcheck added via extraOptions: bash builtin tcp probe against 127.0.0.1:8096,
  no curl/wget dependency on the upstream image
- 30s interval, 5s timeout, 3 retries, 60s start-period
- systemd RestartSec/StartLimitIntervalSec/StartLimitBurst (added in the dep-rewiring commit)
  verified end-to-end with a forced flap
- spec issue #4

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Final Verification

After all five commits land:

- [ ] **Run the full eval check**

```bash
nix flake check 2>&1 | tail -20
```

Expected: no errors.

- [ ] **Confirm the container is healthy and on the pinned image**

```bash
docker inspect jellyfin --format 'image={{.Config.Image}} health={{.State.Health.Status}} status={{.State.Status}}'
```

Expected:

```
image=jellyfin/jellyfin:10.10.7 health=healthy status=running
```

- [ ] **Confirm no orphan units remain**

```bash
systemctl list-unit-files | grep -E 'docker-build-jellyfin|docker-jellyfin-delay|start-jellyfin-stack-delay'
```

Expected: no output (all three units removed).

- [ ] **Confirm dependency chain has no broken references**

```bash
systemd-analyze verify docker-jellyfin.service 2>&1 | grep -i 'home-chin39-mounts\|autofs/data'
```

Expected: no output.

- [ ] **Run task-verifier**

Per repo CLAUDE.md, delegate to the `task-verifier` subagent with a one-line summary:

> "Implemented all 8 stability fixes from `docs/superpowers/specs/2026-05-06-jellyfin-stability-design.md` across 5 commits on `main` (or feature branch); container is healthy, pinned, and dependencies are correct."

If the verifier returns `NOT_VERIFIED`, address each item in `reason` and re-run.
