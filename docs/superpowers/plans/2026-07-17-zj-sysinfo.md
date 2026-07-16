# zj-sysinfo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace zjstatus's fork-heavy `command_net_speed`/`command_uptime` modules with one background wasm plugin that reads `/proc` directly and pushes formatted strings to zjstatus pipe widgets — zero process spawning.

**Architecture:** A Rust crate at `pkgs/zj-sysinfo/` compiled to `wasm32-wasip1`, loaded once per zellij session via `load_plugins`. It requests `FullHdAccess`, repoints `/host` to `/`, samples `/proc/net/{route,dev}` and `/proc/loadavg` every 2 s, and broadcasts `zjstatus::pipe::pipe_*::<text>` payloads that every zjstatus instance renders.

**Tech Stack:** Rust (zellij-tile 0.44.3), wasm32-wasip1, nix (rust-overlay + makeRustPlatform), home-manager.

## Global Constraints

- zellij version on hosts: 0.44.3 → `zellij-tile = "0.44.3"` exactly.
- Build target: `wasm32-wasip1` (zjstatus's flake uses the same).
- The plugin must never panic (background plugin; a panic is silent). Every parse returns `Option`, every failure renders `-`.
- No new flake inputs: reuse the existing `rust-overlay` input (flake.nix:88).
- Repo conventions: crate sources live under `pkgs/zj-sysinfo/` (the `additions` overlay auto-exposes `pkgs.zj-sysinfo`); commit messages end with `Signed-off-by: Ruowen Qin <chinqrw@gmail.com>`, bullet-point bodies, no AI attribution.
- cargo needs crates.io network access — run cargo commands outside the sandbox.
- Verification builds: `nix build --offline --no-link '.#homeConfigurations."chin39@vm-nix".activationPackage'` from `/home/chin39/shell-config` must pass at the end of Tasks 3 and 4. New files must be `git add`ed before nix eval sees them.

---

### Task 1: Parser library with tests

**Files:**
- Create: `pkgs/zj-sysinfo/Cargo.toml`
- Create: `pkgs/zj-sysinfo/src/lib.rs`
- Create: `pkgs/zj-sysinfo/.gitignore` (content: `target/`)

**Interfaces:**
- Produces (used by Task 2's `main.rs`):
  - `pub fn default_iface(route: &str) -> Option<String>`
  - `pub fn iface_bytes(dev: &str, iface: &str) -> Option<(u64, u64)>` — (rx_bytes, tx_bytes)
  - `pub fn loadavg(contents: &str) -> Option<(String, String)>` — (load1, load5)
  - `pub fn rate(prev: u64, cur: u64, elapsed_secs: f64) -> f64` — bytes/s, counter wrap → 0.0
  - `pub fn format_speed(bytes_per_sec: f64) -> String` — e.g. `"1.2 MB/s"`, `"340 KB/s"`, `"12 B/s"`

- [ ] **Step 1: Create the crate with failing tests**

`pkgs/zj-sysinfo/Cargo.toml`:

```toml
[package]
name = "zj-sysinfo"
version = "0.1.0"
edition = "2021"

[dependencies]
zellij-tile = "0.44.3"

[[bin]]
name = "zj-sysinfo"
path = "src/main.rs"
```

Note: `src/main.rs` does not exist yet (Task 2). For this task create a
placeholder so the crate compiles: `pkgs/zj-sysinfo/src/main.rs` with
`fn main() {}` (Task 2 replaces it entirely).

`pkgs/zj-sysinfo/src/lib.rs` — start with ONLY the tests module below plus
empty stubs that `todo!()`, so tests fail first:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    const ROUTE: &str = "\
Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
ens18\t00000000\t0100000A\t0003\t0\t0\t100\t00000000\t0\t0\t0
ens18\t0000000A\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0
docker0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0";

    const DEV: &str = "\
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 1917077    9483    0    0    0     0          0         0  1917077    9483    0    0    0     0       0          0
 ens18: 337403844  436153    0    0    0     0          0      1287 24246047  156373    0    0    0     0       0          0";

    const LOADAVG: &str = "0.52 0.48 0.36 2/1876 123456";

    #[test]
    fn default_iface_picks_zero_destination() {
        assert_eq!(default_iface(ROUTE).as_deref(), Some("ens18"));
    }

    #[test]
    fn default_iface_none_on_empty() {
        assert_eq!(default_iface(""), None);
    }

    #[test]
    fn iface_bytes_parses_rx_tx() {
        assert_eq!(iface_bytes(DEV, "ens18"), Some((337403844, 24246047)));
    }

    #[test]
    fn iface_bytes_none_for_missing_iface() {
        assert_eq!(iface_bytes(DEV, "eth9"), None);
    }

    #[test]
    fn loadavg_takes_first_two_fields() {
        assert_eq!(
            loadavg(LOADAVG),
            Some(("0.52".to_string(), "0.48".to_string()))
        );
    }

    #[test]
    fn rate_computes_bytes_per_second() {
        assert_eq!(rate(1000, 3000, 2.0), 1000.0);
    }

    #[test]
    fn rate_counter_wrap_is_zero() {
        assert_eq!(rate(3000, 1000, 2.0), 0.0);
    }

    #[test]
    fn rate_zero_elapsed_is_zero() {
        assert_eq!(rate(1000, 3000, 0.0), 0.0);
    }

    #[test]
    fn format_speed_units() {
        assert_eq!(format_speed(12.0), "12 B/s");
        assert_eq!(format_speed(340.0 * 1024.0), "340 KB/s");
        assert_eq!(format_speed(1.2 * 1024.0 * 1024.0), "1.2 MB/s");
        assert_eq!(format_speed(2.5 * 1024.0 * 1024.0 * 1024.0), "2.5 GB/s");
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `cd /home/chin39/shell-config/pkgs/zj-sysinfo && cargo test` (sandbox off — needs crates.io for zellij-tile)
Expected: compile error (functions undefined) or `todo!()` panics.

- [ ] **Step 3: Implement the parsers**

Replace the stubs in `pkgs/zj-sysinfo/src/lib.rs` (tests module stays):

```rust
/// First route whose Destination is 00000000 (the default route).
pub fn default_iface(route: &str) -> Option<String> {
    route
        .lines()
        .skip(1)
        .filter_map(|line| {
            let mut cols = line.split_whitespace();
            let iface = cols.next()?;
            let dest = cols.next()?;
            (dest == "00000000").then(|| iface.to_string())
        })
        .next()
}

/// (rx_bytes, tx_bytes) for `iface` from /proc/net/dev contents.
pub fn iface_bytes(dev: &str, iface: &str) -> Option<(u64, u64)> {
    let prefix = format!("{iface}:");
    let line = dev
        .lines()
        .map(str::trim_start)
        .find(|l| l.starts_with(&prefix))?;
    let fields: Vec<&str> = line[prefix.len()..].split_whitespace().collect();
    // Receive: bytes packets errs drop fifo frame compressed multicast (8)
    // Transmit bytes is the 9th field.
    let rx = fields.first()?.parse().ok()?;
    let tx = fields.get(8)?.parse().ok()?;
    Some((rx, tx))
}

/// (load1, load5) from /proc/loadavg contents.
pub fn loadavg(contents: &str) -> Option<(String, String)> {
    let mut fields = contents.split_whitespace();
    let one = fields.next()?.to_string();
    let five = fields.next()?.to_string();
    Some((one, five))
}

/// Bytes/second between two counter samples. Wraps and zero intervals → 0.
pub fn rate(prev: u64, cur: u64, elapsed_secs: f64) -> f64 {
    if elapsed_secs <= 0.0 || cur < prev {
        return 0.0;
    }
    (cur - prev) as f64 / elapsed_secs
}

/// Human-readable speed, matching the old script's style.
pub fn format_speed(bytes_per_sec: f64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = 1024.0 * 1024.0;
    const GB: f64 = 1024.0 * 1024.0 * 1024.0;
    if bytes_per_sec >= GB {
        format!("{:.1} GB/s", bytes_per_sec / GB)
    } else if bytes_per_sec >= MB {
        format!("{:.1} MB/s", bytes_per_sec / MB)
    } else if bytes_per_sec >= KB {
        format!("{:.0} KB/s", bytes_per_sec / KB)
    } else {
        format!("{:.0} B/s", bytes_per_sec)
    }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `cd /home/chin39/shell-config/pkgs/zj-sysinfo && cargo test`
Expected: `test result: ok. 9 passed`

- [ ] **Step 5: Commit**

```bash
cd /home/chin39/shell-config
git add pkgs/zj-sysinfo/Cargo.toml pkgs/zj-sysinfo/Cargo.lock pkgs/zj-sysinfo/src/lib.rs pkgs/zj-sysinfo/src/main.rs pkgs/zj-sysinfo/.gitignore
git commit -m "feat(zj-sysinfo): add /proc parsers for netspeed and load

- default-route interface from /proc/net/route
- rx/tx byte counters from /proc/net/dev with wrap handling
- load averages from /proc/loadavg
- human-readable speed formatting

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>"
```

---

### Task 2: Plugin runtime (main.rs) + wasm build

**Files:**
- Modify: `pkgs/zj-sysinfo/src/main.rs` (replace placeholder entirely)
- Test: manual wasm build (no unit tests — glue code over zellij-tile FFI)

**Interfaces:**
- Consumes: all five `zj_sysinfo::*` functions from Task 1 (exact signatures in Task 1's Produces block).
- Produces: `zj-sysinfo.wasm` binary; pipe payloads
  `zjstatus::pipe::pipe_netspeed::D: <rx> U: <tx>` and
  `zjstatus::pipe::pipe_uptime::<load1> <load5>` (Task 4's layout config
  references widget names `pipe_netspeed` / `pipe_uptime`).

- [ ] **Step 1: Write the plugin runtime**

`pkgs/zj-sysinfo/src/main.rs`:

```rust
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Instant;

use zellij_tile::prelude::*;

use zj_sysinfo::{default_iface, format_speed, iface_bytes, loadavg, rate};

const INTERVAL_SECS: f64 = 2.0;

#[derive(Default)]
struct State {
    granted: bool,
    /// (sample time, rx bytes, tx bytes) of the previous tick.
    prev: Option<(Instant, u64, u64)>,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::FullHdAccess,
            PermissionType::MessageAndLaunchOtherPlugins,
        ]);
        subscribe(&[EventType::Timer, EventType::PermissionRequestResult]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                if !self.granted {
                    self.granted = true;
                    change_host_folder(PathBuf::from("/"));
                    set_timeout(0.0); // first tick immediately
                }
            },
            Event::PermissionRequestResult(PermissionStatus::Denied) => {
                push_widget("pipe_netspeed", "denied");
                push_widget("pipe_uptime", "denied");
            },
            Event::Timer(_) => {
                self.tick();
                set_timeout(INTERVAL_SECS);
            },
            _ => {},
        }
        false // background plugin: nothing to render
    }
}

impl State {
    fn tick(&mut self) {
        push_widget("pipe_netspeed", &self.netspeed_text());
        push_widget("pipe_uptime", &loadavg_text());
    }

    fn netspeed_text(&mut self) -> String {
        let Some(sample) = read_counters() else {
            self.prev = None;
            return "-".to_string();
        };
        let now = Instant::now();
        let (rx, tx) = sample;
        let text = match self.prev {
            Some((at, prev_rx, prev_tx)) => {
                let elapsed = now.duration_since(at).as_secs_f64();
                format!(
                    "D: {} U: {}",
                    format_speed(rate(prev_rx, rx, elapsed)),
                    format_speed(rate(prev_tx, tx, elapsed)),
                )
            },
            None => "-".to_string(),
        };
        self.prev = Some((now, rx, tx));
        text
    }
}

/// rx/tx counters of the default-route interface, read through /host.
fn read_counters() -> Option<(u64, u64)> {
    let route = std::fs::read_to_string("/host/proc/net/route").ok()?;
    let dev = std::fs::read_to_string("/host/proc/net/dev").ok()?;
    let iface = default_iface(&route).or_else(|| fallback_iface(&dev))?;
    iface_bytes(&dev, &iface)
}

/// First non-lo interface with nonzero rx bytes (spec: no-default-route fallback).
fn fallback_iface(dev: &str) -> Option<String> {
    dev.lines().skip(2).find_map(|line| {
        let (name, rest) = line.trim_start().split_once(':')?;
        if name == "lo" {
            return None;
        }
        let rx: u64 = rest.split_whitespace().next()?.parse().ok()?;
        (rx > 0).then(|| name.to_string())
    })
}

fn loadavg_text() -> String {
    std::fs::read_to_string("/host/proc/loadavg")
        .ok()
        .and_then(|s| loadavg(&s))
        .map(|(one, five)| format!("{one} {five}"))
        .unwrap_or_else(|| "-".to_string())
}

/// Broadcast one zjstatus pipe-widget update to all plugins in the session.
fn push_widget(widget: &str, text: &str) {
    // zjstatus's pipe() parses the *payload* with its line protocol; the
    // message name is irrelevant. Newlines would break the protocol.
    let payload = format!("zjstatus::pipe::{widget}::{}", text.replace('\n', " "));
    pipe_message_to_plugin(MessageToPlugin::new("zjstatus").with_payload(payload));
}
```

- [ ] **Step 2: Verify native tests still pass**

Run: `cd /home/chin39/shell-config/pkgs/zj-sysinfo && cargo test`
Expected: `9 passed` (lib tests; main.rs compiles for host target too since
zellij-tile builds natively).

If `cargo test` fails to compile `main.rs` for the host target (zellij-tile
shims are wasm-only stubs on native — they do compile, but if not), gate
the binary: add `#[cfg(target_family = "wasm")]` above `register_plugin!`
and the `impl` blocks is NOT acceptable — instead run
`cargo test --lib` and note it in the commit message.

- [ ] **Step 3: Build the wasm artifact**

```bash
cd /home/chin39/shell-config/pkgs/zj-sysinfo
rustup target add wasm32-wasip1
cargo build --release --target wasm32-wasip1
ls -la target/wasm32-wasip1/release/zj-sysinfo.wasm
```

Expected: the `.wasm` file exists (roughly 0.5–2 MB).

- [ ] **Step 4: Commit**

```bash
cd /home/chin39/shell-config
git add pkgs/zj-sysinfo/src/main.rs pkgs/zj-sysinfo/Cargo.lock
git commit -m "feat(zj-sysinfo): background plugin pushing netspeed/load to zjstatus

- FullHdAccess + change_host_folder('/') for pure-WASI /proc reads
- 2s timer; in-memory counter deltas (no /tmp state files)
- broadcasts zjstatus pipe protocol payloads; never panics, renders '-'
  on any read/parse failure

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>"
```

---

### Task 3: Nix packaging + home-manager install

**Files:**
- Create: `pkgs/zj-sysinfo/default.nix`
- Modify: `pkgs/default.nix` (add one attr)
- Modify: `home-manager/home.nix:168-178` (overlays list — add rust-overlay)
- Modify: `home-manager/programs/zellij/default.nix` (install the wasm)

**Interfaces:**
- Consumes: crate from Tasks 1–2 (`Cargo.lock` must be committed).
- Produces: `pkgs.zj-sysinfo` whose output is `$out/bin/zj-sysinfo.wasm`;
  home file `~/.config/zellij-plugins/zj-sysinfo.wasm` (Task 4's
  `load_plugins` references this exact path).

- [ ] **Step 1: Write the derivation**

`pkgs/zj-sysinfo/default.nix`:

```nix
# Background zellij plugin: pushes netspeed/load to zjstatus pipe widgets.
# Replaces the per-tab `command_*` bash polling that caused the 2026-07-10
# OOM fork storm (docs/superpowers/specs/2026-07-17-zj-sysinfo-design.md).
{
  lib,
  makeRustPlatform,
  rust-bin,
}:
let
  toolchain = rust-bin.stable.latest.minimal.override {
    targets = [ "wasm32-wasip1" ];
  };
  rustPlatform = makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "zj-sysinfo";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = name: _type: baseNameOf name != "default.nix";
  };
  cargoLock.lockFile = ./Cargo.lock;

  buildPhase = ''
    runHook preBuild
    cargo build --release --target wasm32-wasip1
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    cargo test --release
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 target/wasm32-wasip1/release/zj-sysinfo.wasm \
      $out/bin/zj-sysinfo.wasm
    runHook postInstall
  '';
}
```

- [ ] **Step 2: Expose it via the additions overlay**

`pkgs/default.nix` — add one line:

```nix
pkgs: {
  check-xray-version = pkgs.callPackage ./check-xray-version { };
  zj-sysinfo = pkgs.callPackage ./zj-sysinfo { };
}
```

- [ ] **Step 3: Make rust-bin available to home-manager pkgs**

`home-manager/home.nix` — in the `nixpkgs.overlays` list (around line
168), add the rust-overlay BEFORE `outputs.overlays.additions` (the
derivation consumes `rust-bin`):

```nix
    overlays = [
      inputs.rust-overlay.overlays.default
      # ... existing entries unchanged ...
    ];
```

- [ ] **Step 4: Install the artifact next to zjstatus.wasm**

`home-manager/programs/zellij/default.nix` — add to `home.file`:

```nix
    "${config.xdg.configHome}/zellij-plugins/zj-sysinfo.wasm" = {
      source = "${pkgs.zj-sysinfo}/bin/zj-sysinfo.wasm";
    };
```

- [ ] **Step 5: Build gate**

```bash
cd /home/chin39/shell-config
git add pkgs/zj-sysinfo/default.nix pkgs/default.nix
nix build --no-link '.#homeConfigurations."chin39@vm-nix".activationPackage'
```

Expected: success (first run fetches the rust toolchain — do NOT pass
`--offline`). If `rust-bin.stable.latest.minimal` fails on cargoLock
vendoring, the error names the crate — fix Cargo.lock by rerunning
`cargo generate-lockfile` and re-adding.

- [ ] **Step 6: Commit**

```bash
git add pkgs/zj-sysinfo/default.nix pkgs/default.nix home-manager/home.nix home-manager/programs/zellij/default.nix
git commit -m "feat(zj-sysinfo): package wasm plugin and install via home-manager

- build with rust-overlay toolchain targeting wasm32-wasip1
- run native cargo tests in checkPhase
- expose as pkgs.zj-sysinfo through the additions overlay
- install to ~/.config/zellij-plugins/zj-sysinfo.wasm

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>"
```

---

### Task 4: Zellij config switch-over

**Files:**
- Modify: `zellij/config.kdl` (add load_plugins block)
- Modify: `zellij/layouts/play.kdl`
- Modify: `zellij/layouts/side.kdl`
- Modify: `zellij/layouts/dd.kdl`
- Delete: `zellij/net_speed.sh`

**Interfaces:**
- Consumes: widget names `pipe_netspeed` / `pipe_uptime` (Task 2) and the
  installed path `~/.config/zellij-plugins/zj-sysinfo.wasm` (Task 3).

- [ ] **Step 1: Load the plugin at session start**

`zellij/config.kdl` — append at top level (the file has no existing
`load_plugins` block):

```kdl
// Background sysinfo producer for the zjstatus pipe widgets.
// One instance per session replaces the per-tab command_* bash polling
// that caused the 2026-07-10 OOM fork storm.
load_plugins {
    "file:~/.config/zellij-plugins/zj-sysinfo.wasm"
}
```

- [ ] **Step 2: Swap widgets in all three layouts**

In each of `zellij/layouts/play.kdl`, `zellij/layouts/side.kdl`,
`zellij/layouts/dd.kdl`:

1. In `format_left`/`format_right` strings: replace the handle
   `{command_net_speed}` with `{pipe_netspeed}` and `{command_uptime}`
   with `{pipe_uptime}` (keep surrounding color codes byte-identical).
2. Delete every line starting with `command_uptime_` or
   `command_net_speed_` (command/format/interval/rendermode).
3. Add in their place (same indentation as neighboring widget config):

```kdl
                pipe_netspeed_format      "#[fg=blue] {output} "
                pipe_netspeed_rendermode  "static"

                pipe_uptime_format      "#[fg=blue] {output} "
                pipe_uptime_rendermode  "static"
```

(`#[fg=blue] {output} ` matches the old `command_*_format` styling —
verify against each file and keep whatever color each layout used.)

`command_git_branch_*` lines stay untouched.

- [ ] **Step 3: Remove the script**

```bash
git rm zellij/net_speed.sh
grep -rn "net_speed" /home/chin39/shell-config/zellij /home/chin39/shell-config/home-manager
```

Expected: grep finds nothing (the only consumer was the deleted
`command_net_speed_command` lines; the `home.file` entry symlinks the whole
`zellij/` dir so no per-file reference exists).

- [ ] **Step 4: Build gate**

```bash
cd /home/chin39/shell-config
nix build --offline --no-link '.#homeConfigurations."chin39@vm-nix".activationPackage'
```

Expected: success.

- [ ] **Step 5: Commit**

```bash
git add zellij/config.kdl zellij/layouts/play.kdl zellij/layouts/side.kdl zellij/layouts/dd.kdl
git commit -m "feat(zellij): switch netspeed/uptime widgets to zj-sysinfo pipes

- load zj-sysinfo as a background plugin at session start
- replace command_net_speed/command_uptime with pipe widgets in all
  three layouts
- drop net_speed.sh (per-tab bash polling, 2026-07-10 OOM root cause)

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>"
```

---

### Task 5: Runtime acceptance on vm-nix

**Files:**
- Possibly modify: `pkgs/zj-sysinfo/src/main.rs` (fixes found at runtime)
- Modify: `/home/chin39/.claude/projects/-home-chin39-shell-config/memory/project_oom_2026-07-10_fork_storm.md` (record resolution)

**Interfaces:**
- Consumes: everything above, applied via `home-manager switch`.

- [ ] **Step 1: Apply**

```bash
cd /home/chin39/shell-config
home-manager switch --flake '.#chin39@vm-nix'
```

Expected: activation succeeds; `~/.config/zellij-plugins/zj-sysinfo.wasm`
exists.

- [ ] **Step 2: Verify in a throwaway session**

```bash
zellij -s zjtest -n play
```

Inside: watch the status bar. Within ~4 s both widgets must show live
values (`D: … U: …` and two load numbers).

**Permission gate check (spec's Known risk):** if widgets stay empty,
inspect `zellij.log` (`ls -t /tmp/zellij-1000/zellij-log/ | head`) for a
pending permission request. If the background plugin cannot prompt:
grant once by loading it in a visible pane —
`zellij -s zjtest action new-pane --plugin "file:~/.config/zellij-plugins/zj-sysinfo.wasm"`
— approve, close the pane, restart the session. Document whichever path
worked as a comment in `zellij/config.kdl` next to `load_plugins`.

- [ ] **Step 3: Verify zero forking via audit**

```bash
sleep 120; journalctl -t audit --since "2 minutes ago" --no-pager \
  | grep -F 'SYSCALL' | grep -F 'comm="bash"' | grep -oP 'ppid=\d+' \
  | sort | uniq -c | sort -rn | head -5
```

Expected: the zjtest session's zellij server PID contributes ZERO bash
(only `git_branch` remains, at most ~6/min per tab; the old `play` session
still shows the old rate until it is restarted — note this to the user).

- [ ] **Step 4: Kill-safety check**

Detach and kill the test session: `zellij kill-session zjtest`. Re-attach
to a fresh one; widgets must repopulate. In the fresh session confirm no
`/tmp/rx_prev` / `/tmp/tx_prev` files are recreated:
`ls /tmp/rx_prev /tmp/tx_prev` → both must be "No such file" (old script
artifacts may linger from before — delete them: `rm -f /tmp/rx_prev /tmp/tx_prev`).

- [ ] **Step 5: Update the incident memory and commit fixes**

Append to the memory file's body: plugin shipped, date, and that the
remaining exec source is `command_git_branch` only. Commit any main.rs
fixes made during acceptance:

```bash
git add -A pkgs/zj-sysinfo zellij
git commit -m "fix(zj-sysinfo): runtime fixes from vm-nix acceptance

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>"
```

(Skip the commit if there were no fixes.)

---

## Self-Review

- Spec coverage: parsers+fallback (Task 1/2), permissions+change_host_folder (Task 2), nix+HM install (Task 3), load_plugins+layout swap+script deletion (Task 4), permission-risk mitigation+audit acceptance (Task 5). Non-goals untouched. ✓
- No placeholders; every code step carries full code. ✓
- Names consistent across tasks: `pipe_netspeed`/`pipe_uptime`, `pkgs.zj-sysinfo`, `$out/bin/zj-sysinfo.wasm`, five parser signatures. ✓
