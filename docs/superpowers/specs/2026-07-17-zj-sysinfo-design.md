# zj-sysinfo: zero-fork netspeed/uptime for the zellij status bar

Date: 2026-07-17
Status: approved

## Problem

The zjstatus status bar shows net speed and load averages via `command_*`
modules that fork `bash -c` pipelines on 1–2 s timers, **per zjstatus
instance (= per tab)**. Measured via auditd: ~20 bash/s, 250–370 execs/s
sustained (~8 instances). Under memory pressure on 2026-07-10 these
fire-and-forget children piled up to ~2,200 live bash processes and caused
a 10-minute OOM storm (see memory: oom-2026-07-10-fork-storm). The exec
flood also rotates the journal (~3.9 GiB/day of audit records).

Research (2026-07-17): no existing plugin provides netspeed/uptime for
zjstatus. Closest is zellij-load (CPU/MEM/GPU, native daemon + own widget,
not zjstatus-integrated). zjstatus has no native net/load widgets, but its
`pipe` widget is designed for external data sources.

## Goal

Keep the exact functionality (net speed of the default interface + load
averages, ~2 s freshness) with **zero process spawning**: one background
wasm plugin per session computes the strings and pushes them to every
zjstatus instance.

## Verified API facts (zellij v0.44.3 source, zjstatus main)

- `/host` in the plugin WASI env is a preopened dir; `change_host_folder()`
  (zellij-tile shim.rs:2457) repoints it at runtime; gated by the
  `FullHdAccess` permission → pure-WASI reads of `/proc/*`.
- `set_timeout(secs)` (shim.rs:810) provides timer ticks.
- `pipe_message_to_plugin(MessageToPlugin)` (shim.rs:1590) delivers pipe
  messages; zjstatus `pipe()` (src/bin/zjstatus.rs:117) treats
  `PipeSource::Plugin` identically to CLI: the **payload** goes through
  `parse_protocol`, format `zjstatus::pipe::pipe_<NAME>::<content>`.
- zjstatus widget config: `pipe_NAME_format`, `pipe_NAME_rendermode`;
  handle `{pipe_NAME}`.

## Architecture

One new Rust crate compiled to `wasm32-wasip1`, loaded once per session as
a background plugin. Data flow:

```
/proc/net/route ─┐
/proc/net/dev  ──┼─> zj-sysinfo (1 instance/session, tick 2 s)
/proc/loadavg  ──┘        │ pipe_message_to_plugin (broadcast)
                          v
        zjstatus instances (per tab) render {pipe_netspeed} {pipe_uptime}
```

## Components

### 1. Plugin crate: `zellij/zj-sysinfo/`

- `zellij-tile` SDK matching zellij 0.44.x; `#[derive(Default)] State` +
  `register_plugin!`.
- `load()`: `request_permission(&[FullHdAccess, MessageAndLaunchOtherPlugins])`,
  subscribe to `PermissionRequestResult` and `Timer`.
- On permission grant: `change_host_folder("/")`, first `set_timeout(2.0)`.
- Each tick:
  1. Parse `/host/proc/net/route`: default interface = first entry with
     destination `00000000`.
  2. Parse `/host/proc/net/dev`: rx/tx bytes for that interface; delta
     against previous tick held in plugin memory (no /tmp files); divide by
     actual elapsed time, not nominal interval.
  3. Parse `/host/proc/loadavg`: fields 1–2 (load1, load5).
  4. Push two messages, payloads:
     - `zjstatus::pipe::pipe_netspeed::D: <rx>/s U: <tx>/s`
     - `zjstatus::pipe::pipe_uptime::<load1> <load5>`
  5. `set_timeout(2.0)` again.
- Speed formatting: B/s / KB/s / MB/s / GB/s, matching current script
  output style (`D: x U: y`).
- Parsers live in `lib.rs` as pure functions (string in → value out) so
  they unit-test natively without a wasm runtime.

### 2. Nix packaging

- Derivation in shell-config building the crate with the existing
  `rust-overlay` input providing the `wasm32-wasip1` target
  (same pattern zjstatus's flake uses).
- home-manager installs the artifact at
  `~/.config/zellij-plugins/zj-sysinfo.wasm`
  (`home-manager/programs/zellij/default.nix`, next to zjstatus.wasm).

### 3. Config changes

- `zellij/config.kdl`: add `load_plugins` entry for
  `file:~/.config/zellij-plugins/zj-sysinfo.wasm` (background load at
  session start).
- Layouts `play.kdl`, `side.kdl`, `dd.kdl`:
  - `{command_net_speed}` → `{pipe_netspeed}`; `{command_uptime}` →
    `{pipe_uptime}` in format strings.
  - Remove `command_net_speed_*` and `command_uptime_*` lines; add
    `pipe_netspeed_format` / `pipe_uptime_format` (+ `rendermode static`)
    preserving current colors.
  - `command_git_branch` stays (10 s, harmless volume).
- Delete `zellij/net_speed.sh` and its installation reference.

## Error handling

- Any parse failure → push `-` for that widget; never panic (a background
  plugin panic is invisible).
- No default route → fall back to the first non-`lo` interface with
  nonzero traffic; none → `-`.
- Permission denied / missing FullHdAccess → log via `eprintln!` (lands in
  zellij.log) and retry permission request once.
- Counter wrap/reset (interface restart): negative delta → treat as 0.

## Known risk

Background plugins have no pane, so the interactive permission-grant UI
may not appear. Mitigations, in order: (a) load the plugin once in a
visible pane to grant + cache permissions, then rely on zellij's
permission cache; (b) write the permission cache declaratively from
home-manager. Implementation must verify (a) or (b) and document the
choice in the module comment.

## Testing

- Unit tests (native `cargo test`): route parser, net/dev parser, loadavg
  parser, speed formatter, delta/wrap logic — fixture strings from a real
  vm-nix `/proc`.
- Build gates: `cargo build --target wasm32-wasip1` via nix; full
  home-manager closure builds.
- Acceptance: in a new session, both widgets update every ~2 s; auditd
  shows zellij-server bash spawn rate ≈ 0 (only git_branch remains);
  killing the plugin (reload) does not wedge zjstatus (widgets freeze at
  last value — acceptable).

## Non-goals

- Memory/CPU/GPU widgets (zellij-load exists for that).
- Replacing zjstatus or its other modules.
- Upstreaming to zjstatus (possible later; out of scope).
