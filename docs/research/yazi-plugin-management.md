# How yazi manages plugins/packages today (and whether our setup is current)

Research date: **2026-09-17**.
Author: delegated research agent. Scope: plugin/flavor installation and discovery in upstream yazi, judged against this repo's `yazi/` config.

## 0. Versions, commit pinning and method

| Thing | Value | How observed |
| --- | --- | --- |
| Deployed `yazi`/`ya` | `26.9.1 (a228e69 2026-09-16)`, `aarch64-apple-darwin`, via `/nix/store/140sxcqdiwny986di05r8nl040kchz4i-yazi-26.9.1pre20260916_a228e69` | `yazi --version`, `ya --version` (local) |
| Upstream `main` HEAD while researching | `a228e69df26b9b9a68de6805099c471af5a86719` — *the same SHA* | `git clone --depth 1 https://github.com/sxyazi/yazi.git` → `git rev-parse HEAD` |
| Docs version matching the deployed build | site version selector `26.9.1` (`versioned_docs/version-26.9.1/`) | https://yazi-rs.github.io/docs/cli |

**Divergence note:** there is *no* divergence between the deployed pre-release build and upstream `main` at the time of research — `26.9.1pre20260916_a228e69` is literally upstream `main` @ `a228e69`. Everything cited below from `yazi-rs.github.io` version `26.9.1` matches the deployed binary except the docs' own known stale bullets (see §2.3 and §5.5, where the docs and the code disagree — I flag those explicitly). Source links are pinned to `a228e69` so they stay valid.

**Canonical org correction (asked in the task):** the upstream repository is **`github.com/sxyazi/yazi`**, *not* `yazi-rs/yazi` (that URL 404s/proxies). `yazi-rs` is a *different* org used for satellites: `yazi-rs/plugins` (the plugin marketplace monorepo we `use` in `package.toml`), `yazi-rs/schemas` (the TOML JSON schema), `yazi-rs/yazi-rs.github.io` (the docs site). Evidence: the docs' GitHub link in the site header is `https://github.com/sxyazi/yazi`, and the docs' "Yazi Preset Plugins" link is `https://github.com/sxyazi/yazi/tree/shipped/yazi-plugin/preset/plugins`.

## 1. Current official way to install/manage plugins and flavors

Official docs page: <https://yazi-rs.github.io/docs/cli#pm>. First-party CLI surface, verbatim from the deployed build:

```
$ ya pkg --help
Manage packages

Usage: ya pkg <COMMAND>

Commands:
  add      Add packages
  delete   Delete packages
  install  Install all packages
  list     List all packages
  upgrade  Upgrade all packages
  help     Print this message or the help of the given subcommand(s)
```

Per-subcommand flags as deployed (`ya pkg <cmd> --help`):

| Command | Usage | Flags |
| --- | --- | --- |
| `add` | `ya pkg add [IDS]...` | — |
| `delete` | `ya pkg delete [IDS]...` | `--discard` |
| `install` | `ya pkg install` | `--discard` |
| `list` | `ya pkg list` | — |
| `upgrade` | `ya pkg upgrade [IDS]...` | `--discard` |

- `add`/`delete` accept multiple IDs (`ya pkg add owner/plugin yazi-rs/plugins:git`) — docs, <https://yazi-rs.github.io/docs/cli#pm>, and `args.rs` uses `num_args = 1..` ([`yazi-cli/src/args.rs#L72-L103`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/args.rs#L72-L103)).
- `upgrade` accepts ids ("upgrade all if unspecified") — added in [#2841](https://github.com/sxyazi/yazi/pull/2841) (v25.12.29).
- `--discard` = "Discard local changes made to packages" — added in [#3781](https://github.com/sxyazi/yazi/pull/3781) (v26.5.6).
- **`ya pkg verify` does not exist.** It is absent from `ya pkg --help`, absent from `CommandPkg` in `args.rs`, and absent from the docs page; the only string "verify" in the docs site is unrelated (`docs/image-preview.md`). Do not put `ya pkg verify` in scripts.
- Flavors use the same commands; a package is classified as a flavor only if the checked-out source contains `flavor.toml` ([`deploy.rs#L15-L17`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/deploy.rs#L15-L17)), and flavors land in `<config>/flavors/<name>.yazi` ([`dependency.rs#L35-L40`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L35-L40)).
- `ya pkg` requires **`git`** on `PATH` and network access to GitHub: the remote is hard-coded to `https://github.com/{owner}/{repo}.git` ([`dependency.rs#L30-L33`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L30-L33)); clone/checkout is done by shelling out to `git` with pinned config ([`git.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/git.rs)).

## 2. The exact current `package.toml` schema

Authoritative source is the serde definitions, not the docs: [`yazi-cli/src/package/package.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/package.rs) and [`dependency.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs).

### 2.1 Shape

```toml
[[plugin.deps]]      # 0..n
use  = "owner/repo"        # or "owner/repo:child"
rev  = "6af9bf2"           # optional (serde default ""), git revision of the source repo
hash = "336548d9f67926e12d5584f60b790f1"  # optional (serde default ""), 128-bit lock over deployed files

[flavor]
deps = []            # 0..n, same Dependency record, classified as flavor
```

- The deserializer reads exactly `plugin.deps` and `flavor.deps` (`struct Outer { plugin: Shadow, flavor: Shadow }`, `struct Shadow { deps: Vec<Dependency> }`) — [`package.rs#L146-L166`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/package.rs#L146-L166). Entries under `[flavor]` are flagged `is_flavor = true`.
- `use` is **required**; `rev` and `hash` are `#[serde(default)]` — [`dependency.rs#L128-L141`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L128-L141).
- The file lives at `<config_dir>/package.toml` ([`package.rs#L138`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/package.rs#L138)); a missing file is tolerated (defaults to an empty `Package`).
- The serializer emits exactly the shape above, always writing `[flavor] deps` even when empty ([`package.rs#L170-L186`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/package.rs#L170-L186)).
- **No field is deprecated and none was newly made required.** The schema has been stable since the package manager landed; what changed is the *fetcher rule* schema in `yazi.toml`, which is a different file (§7).

### 2.2 Meaning of each field, and the relation to the on-disk layout

- `use = "owner/repo"` → the Git repo fetched is **`owner/repo.yazi`** (note the `.yazi` suffix is appended when no `:child` is given: `parent: format!("{parent}{}", if child.is_empty() { ".yazi" } else { "" })`, [`dependency.rs#L115-L120`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L115-L120)). Plugin directory name = `repo.yazi` (or `child.yazi`).
- `use = "owner/repo:child"` → fetch `owner/repo`, then take the `child.yazi/` subdirectory of it (monorepo layout, e.g. `yazi-rs/plugins:git` → the `git.yazi/` folder of `yazi-rs/plugins`). Name must be kebab-case (`[0-9a-z-]`, [`yazi-shared/src/bytes.rs#L32-L34`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-shared/src/bytes.rs#L32-L34)).
- `rev` = the git revision **of the source repo** (short SHA written by `git rev-parse --short HEAD`, [`git.rs#L30-L45`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/git.rs#L30-L45)). Semantics per subcommand: `install` checks the pinned `rev` out if non-empty, and only fills `rev` from HEAD when it was empty ([`install.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/install.rs)); `add`/`upgrade` pull the upstream default branch and then refresh `rev` unconditionally ([`add.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/add.rs)). A literal `=` prefix **pins** it: `upgrade` returns early if `rev.starts_with('=')` ([`upgrade.rs#L7`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/upgrade.rs#L7)); documented at <https://yazi-rs.github.io/docs/cli#pm>.
- `hash` = lock/hash of the **deployed** plugin (or flavor) directory contents: XXH3-128 over the whitelisted files in sorted order with per-file/per-asset separators ([`hash.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/hash.rs)). Before any write, `install`/`upgrade`/`delete` re-hash the target dir and abort if it differs from `hash`:
  > "You have modified the contents of the `{name}` plugin. For safety, the operation has been aborted. Please manually delete it from … or use `--discard` …" ([`hash.rs#L45-L52`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/hash.rs#L45-L52))
- Deployment layout: source cache is `$XDG_CACHE_HOME/yazi/packages/<xxh3_128(remote-url)>` ([`dependency.rs#L24-L28`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L24-L28), [`package/mod.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/mod.rs)); the deployed target is `<config_dir>/plugins/<name>.yazi` or `<config_dir>/flavors/<name>.yazi` ([`dependency.rs#L35-L40`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L35-L40)).
- `ya pkg` copies only a **whitelist** of files into the target: `LICENSE`, `README.md`, `main.lua`, plus every other *top-level* `*.lua` whose stem is kebab-case, plus a flat `assets/` directory; flavors instead get `LICENSE`, `LICENSE-tmtheme`, `README.md`, `flavor.toml`, `preview.png`, `tmtheme.xml` ([`dependency.rs#L67-L88`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/dependency.rs#L67-L88), [`deploy.rs#L47-L75`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/deploy.rs#L47-L75)). Consequence: a plugin whose upstream repo lacks `LICENSE`/`README.md`/`main.lua`, or keeps Lua in subdirectories, cannot be installed by `ya pkg`.
- Deployed files are written **read-only** (`perm.set_readonly(true)`, [`shared.rs#L20-L31`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/shared/shared.rs#L20-L31)); observed after a real `ya pkg install`: `-r--r--r--` on all deployed plugin files.

### 2.3 Docs-vs-code discrepancy you should know about

The docs list a fetcher-rule key `if` ("Run the fetcher only if the condition is met") — <https://yazi-rs.github.io/docs/configuration/yazi#plugin.fetchers>. **The code at the deployed commit has no `if` field on fetcher rules** (see §5.4); fetch conditions were removed from the schema years ago (present in `v0.4.0`/`v0.3.3`, gone by `v25.2.7`). Treat the docs bullet as stale; the schema authority is [`yazi-config/src/plugin/fetcher.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/src/plugin/fetcher.rs).

## 3. Was `ya pack` renamed to `ya pkg`?

Yes, and `ya pack` is **gone** in the deployed build.

| Event | Version | Evidence |
| --- | --- | --- |
| `ya pack` introduced with the first package manager | commit `faa1d9f37` "feat: package manager (#985)", 2024-05-07 | [commit list for `yazi-cli/src/args.rs`](https://github.com/sxyazi/yazi/commits/main/yazi-cli/src/args.rs) |
| `ya pkg` added | `70e459a01` "feat: new `ya pkg` subcommand ([#2770](https://github.com/sxyazi/yazi/pull/2770))", 2025-05-17 → shipped in **v25.5.28** | same; CHANGELOG `## [v25.5.28] → Added` / `Deprecated` |
| `ya pack` publicly deprecated in favour of `ya pkg` | v25.5.28 | CHANGELOG: "Deprecate the `ya pack` subcommand in favor of `ya pkg` ([#2770])" ([CHANGELOG.md](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/CHANGELOG.md)) |
| `ya pack` kept temporarily as a **hidden** alias (`#[command(hide = true)]`, `// TODO: remove`) | v25.5.28, v25.5.31 | `yazi-cli/src/args.rs` at tag `v25.5.31`: `Pack(CommandPack), // TODO: remove` |
| Hidden alias **deleted** | commit `37134787532aecba20a239b137a216b06e76f596` "feat: multi-entry support for plugin system ([#3154](https://github.com/sxyazi/yazi/pull/3154))", 2025-09-08 → first release without it: **v25.12.29** | removed in that commit's diff of `args.rs` (−23 lines); `args.rs` at `v25.12.29` contains no `Pack` |

Deployed behaviour (run locally):

```
$ ya pack --help
error: unrecognized subcommand 'pack'          [exit 2]
$ ya pack
error: unrecognized subcommand 'pack'          [exit 2]
```

So: no, `ya pack` is not accepted — not even as a hidden alias — in the deployed build.

## 4. Which plugins ship built into yazi? Is `mime` builtin?

### 4.1 The authoritative builtin list

There is no config file for this; builtins are hard-coded in the loader's initial cache: [`yazi-runner/src/loader/loader.rs#L27-L95`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L27-L95) (`Loader::default()`, installed at startup by `yazi-runner/src/loader/mod.rs`). Sources for these are embedded at build time from `yazi-plugin/preset/plugins/*.lua` via the `plugin_preset!` macro ([`yazi-macro/src/asset.rs#L29-L45`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-macro/src/asset.rs#L29-L45)), which is why the nix `share/` dir is empty — nothing is read from disk for them.

Builtin **plugin** names at `a228e69` (34):

```
archive  clipboard  code  dds  dnd  empty  error  extract  fd  file  folder  font
fzf  go  image  init  json  magick  mime  mime.dir  mime.local  mime.remote  mime.trash
multi  noop  pdf  rg  search  session  svg  trash  vfs  video  zoxide
```

Builtin **UI component** names: `app backdrop current entity header linemode marker markers modal parent preview progress rail rails root status tab tabs tasks tip`.
Reserved (empty) names: `history inline none null sftp`.
The docs' "Builtins" page only describes `fzf` and `zoxide` (<https://yazi-rs.github.io/docs/plugins/builtins>); the loader registry above is the complete list.

Note that the *default* `yazi.toml` already wires all MIME fetching to builtins — `fetchers` = `{ url = "*/", run = "mime.dir" }`, `{ url = "local://*", run = "mime.local" }`, `{ url = "trash://*", run = "mime.trash" }`, `{ url = "remote://*", run = "mime.remote" }`, all with `group = "mime"` ([`yazi-config/preset/yazi-default.toml`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/preset/yazi-default.toml), `[plugin] fetchers`).

### 4.2 The `mime` name specifically — definitive answer

The `mime` name *is* registered as a builtin, so no `plugins/mime.yazi/` directory is needed for `run = "mime"` to **resolve** — and, because builtins are consulted first (§5.2), a `plugins/mime.yazi/` directory would **never be read** for that name anyway. But the name is now a tombstone. History, verified per release tag:

| Version | `yazi-plugin/preset/plugins/mime.lua` |
| --- | --- |
| ≤ v25.5.31 | **Real plugin** (1435 bytes): `M:fetch` runs `file -bL --mime-type` over the batch |
| v25.12.29 – v26.1.22 | **Deprecation shim** (342 bytes): notifies "The `mime` fetcher is deprecated, use `mime.local` instead in your `yazi.toml`" (points at [#3222](https://github.com/sxyazi/yazi/pull/3222)) then delegates to `require("mime.local"):fetch(job)` |
| v26.5.6 – main@`a228e69` | **Empty file, 0 bytes** — the shim was emptied in commit `face6aed40b3` (PR [#3608](https://github.com/sxyazi/yazi/pull/3608), 2026-01-24) |

The rename itself was a breaking change in v25.12.29: "Rename `mime` fetcher to `mime.local`, and introduce `mime.dir` fetcher to support folder MIME types ([#3222](https://github.com/sxyazi/yazi/pull/3222))" (CHANGELOG `## [v25.12.29] → Changed`; commit `4d39194cd81d` is titled `feat!: folder mime-type support`).

**Therefore:** `plugins/mime.yazi/` is *not* required, was never consulted even when it existed as a name, and `run = "mime"` is a dead name at the deployed commit (the embedded chunk evaluates to nothing — `Loader::load_new` requires the chunk to produce a table, [`loader.rs#L139-L165`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L139-L165)). The correct current names are `mime.local` / `mime.dir` / `mime.trash` / `mime.remote`, which the built-in default config already uses.
*Not executed:* I could not run the TUI to capture the exact runtime error for `run = "mime"` (this sandbox denies PTY allocation — `script: openpty: Operation not permitted`, Python `pty.fork()` likewise), so the empty-chunk conclusion is from source reading, not from a live run.

## 5. How the plugin loader discovers plugins

### 5.1 Config directory

`Xdg::config_dir()`: `$YAZI_CONFIG_HOME` if set **and absolute**, else `$XDG_CONFIG_HOME/yazi` (also must be absolute), else `~/.config/yazi` ([`yazi-fs/src/xdg.rs#L21-L44`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-fs/src/xdg.rs#L21-L44)). The cache dir used by `ya pkg` is `$XDG_CACHE_HOME/yazi` (else `~/.cache/yazi`).

### 5.2 Path and name resolution (unchanged in shape, but with hard rules)

- Plugins live at `<config_dir>/plugins/<name>.yazi/<entry>.lua` — [`loader.rs#L106`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L106). Documented identically at <https://yazi-rs.github.io/docs/plugins/overview> ("plugins subdirectory of Yazi's configuration directory", `bar.yazi/main.lua`).
- Entry selection: a *dot* in the rule's plugin name selects a non-`main` entry file (multi-entry plugins, [#3154](https://github.com/sxyazi/yazi/pull/3154)). `explode_name_parts` strips a trailing `.main`, then splits on the **first** `.`: `mime.dir` → plugin `mime`, entry `dir` → `mime.yazi/dir.lua`; a bare `git` → `git.yazi/main.lua` ([`loader.rs#L190-L197`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L190-L197)).
- Plugin name and entry name must be **kebab-case** (`[0-9a-z-]` only — no uppercase, no underscore, no dots beyond the separator), else a hard error ([`loader.rs#L195-L196`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L195-L196)).
- **Builtin names win unconditionally:** `ensure()` checks the in-memory cache (pre-seeded with all builtins) *before* touching the filesystem, and nothing ever inserts user plugin dirs into that cache at startup. So a user-installed directory that shadows a builtin name (`mime.yazi`, `code.yazi`, `fzf.yazi`, …) is silently ignored. *(Source-derived; not executed, no PTY available.)*
- Plugins that are **not** builtin (`git`, `ouch`, `augment-command`, `time-travel`, `mime-ext`, …) are read from disk on first use and cached in memory.
- `init.lua` is **no longer a plugin entry file** — deprecated in favour of `main.lua` in v25.2.7 ([#2168](https://github.com/sxyazi/yazi/pull/2168), CHANGELOG "Deprecate plugin entry file `init.lua` in favor of `main.lua`"), and the loader only reads `<entry>.lua`. The *config-level* `~/.config/yazi/init.lua` is a separate thing (executed directly, [`yazi-plugin/src/standard.rs#L74-L75`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-plugin/src/standard.rs#L74-L75)) and is unaffected.
- `require("name")` inside Lua uses the same loader ([`loader/require.rs#L11-L25`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/require.rs#L11-L25)), so `require("git")` resolves to the user dir.
- `@since <version>` annotations in a plugin are enforced at load time ([`loader.rs#L167-L177`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/loader.rs#L167-L177)); `@sync entry|peek` is parsed from the chunk header ([`chunk.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-runner/src/loader/chunk.rs)).

### 5.3 Environment variables

- `YAZI_CONFIG_HOME` — yes, and it must be an absolute path.
- **`YAZI_PLUGINS_DIR` does not exist.** A repo-wide grep for `YAZI_PLUGINS_DIR` (Rust, Markdown, TOML) returns nothing; the only plugin-location input is the config dir. (Note: in a *plugin process* yazi sets `YAZI_ID`/`YAZI_PID`-style vars for DDS, but no plugin search path.)

### 5.4 The `[plugin]` rule schema in `yazi.toml` (this is what actually broke in our repo)

Fetcher rules at `a228e69` ([`yazi-config/src/plugin/fetcher.rs#L13-L22`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/src/plugin/fetcher.rs#L13-L22)):

| Key | Required? | Meaning |
| --- | --- | --- |
| `url` / `mime` | at least one ([`selector.rs#L37-L40`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/src/selector.rs#L37-L40)) | match pattern |
| `run` | yes | plugin name |
| `prio` | no (`#[serde(default)]`) | `high`/`normal`/`low` |
| `group` | **yes** (`group: String`, no default) | only the first matching fetcher per group runs (`Fetchers::mime` selects `group == "mime"`, [`fetchers.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/src/plugin/fetchers.rs)) |
| `id` | ignored (`#[serde(skip)]`) | replaced by `group` in [#3943](https://github.com/sxyazi/yazi/pull/3943) (v26.5.6) |
| `cond` / `if` | **not a field** | never existed as `cond`; `if` existed only up to v0.4.0-era code |

The section keys are `fetchers`, `prepend_fetchers`, `append_fetchers`, and the same trio for `spotters`, `preloaders`, `previewers` ([`yazi-config/src/plugin/plugin.rs#L10-L34`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-config/src/plugin/plugin.rs#L10-L34)). A key named `prefetchers` has never existed in any version I checked (`v0.1.6`, `v0.2.5`, `v0.3.3`, `v0.4.0`, `v25.2.7`, `v25.5.31`, `v25.12.29`, `v26.5.6`, `v26.8.15`, `main@a228e69` — no match for `prefetch` in `yazi-config/src/plugin/plugin.rs`).

Unknown keys do **not** error: the `DeserializeOver2` codegen routes unrecognized keys to `IgnoredAny` ([`yazi-codegen/src/lib.rs#L50`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-codegen/src/lib.rs#L50), `_ => _ = map.next_value::<IgnoredAny>()?`). So a mistyped rule key is silently dropped rather than reported.

## 6. Is hand-vendoring still supported? What about read-only / Nix-managed config dirs?

**Yes — vendoring directories is fully supported and is upstream's own documented approach for Nix users.**

- The loader's only requirement is the on-disk path `<config>/plugins/<name>.yazi/<entry>.lua` (§5.2). It does not consult `package.toml`, does not check hashes, and has no notion of "installed by `ya pkg`". `package.toml` is read **only** by the `ya` CLI ([`yazi-cli/src/package/mod.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-cli/src/package/mod.rs) — `package::init()` is called only from `Command::Pkg`).
- Git submodule/tracked-directory vendoring is therefore legitimate. Caveats:
  - `ya pkg`-listed dirs are hash-checked and will abort with "You have modified the contents…" if the vendored tree differs from the recorded `hash`; conversely if a dir *is* listed, `ya pkg install/upgrade/delete` will rewrite or delete it (delete keeps unknown files and prints "For safety, user data will be preserved").
  - `ya pkg` writes to `<config_dir>` and `$XDG_CACHE_HOME/yazi`; it seals deployed files read-only.
- **Upstream's own Nix guidance is vendoring.** The docs' Nix section ships a home-manager template that fetches plugins with `pkgs.fetchFromGitHub` and assigns store paths, no `package.toml` anywhere:
  > `plugins = { chmod = "${yazi-plugins}/chmod.yazi"; full-border = "${yazi-plugins}/full-border.yazi"; toggle-pane = "${yazi-plugins}/toggle-pane.yazi"; starship = pkgs.fetchFromGitHub { … }; };`
  — <https://yazi-rs.github.io/docs/installation#nix> (source: `docs/installation.md` in `yazi-rs/yazi-rs.github.io`). The same page documents home-manager's `programs.yazi.enable` option.
- Upstream says **nothing explicit** about read-only config directories (no FAQ/issue/CHANGELOG statement found; the docs never mention immutability). The Nix example is the closest thing to an endorsement, and it implies "the loader reads whatever is at `plugins/`, however it got there". Anything beyond that is **unresolved** — what would settle it: an upstream issue/PR discussing `ya pkg` under Nix/immutable configs, which I did not find.

## 7. Breaking changes affecting plugin management / `[plugin]` in the last ~12 months

All from [CHANGELOG.md @ a228e69](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/CHANGELOG.md) unless noted.

| Release | Change | Impact |
| --- | --- | --- |
| v25.12.29 | `name` → `url` for fetchers, spotters, preloaders, previewers, open/filetype/globs icon rules ([#3034](https://github.com/sxyazi/yazi/pull/3034)) | any rule still using `name = "*"` silently matches nothing |
| v25.12.29 | **`mime` fetcher → `mime.local`; new `mime.dir`** ([#3222](https://github.com/sxyazi/yazi/pull/3222), commit titled `feat!:`) | `run = "mime"` deprecated, then tombstoned (§4.2) |
| v25.12.29 | Multi-entry plugin support ([#3154](https://github.com/sxyazi/yazi/pull/3154)) → `plugin.entry` naming; the same commit deleted the hidden `ya pack` alias | plugins may now expose `foo.yazi/<entry>.lua` |
| v25.12.29 | `ya pkg upgrade [IDS]` ([#2841](https://github.com/sxyazi/yazi/pull/2841)); force Git checkout in the package cache ([#3169](https://github.com/sxyazi/yazi/pull/3169)); renew `rev` only when empty ([#3200](https://github.com/sxyazi/yazi/pull/3200)) | CLI behaviour |
| v26.1.4 | `ya pkg` now creates the config dir if missing ([#3482](https://github.com/sxyazi/yazi/pull/3482)) | CLI behaviour |
| v26.5.6 | **Fetcher rule `id` renamed to `group`; `group` is now required** ([#3943](https://github.com/sxyazi/yazi/pull/3943)) | a fetcher rule without `group` fails to parse |
| v26.5.6 | `ya pkg … --discard` ([#3781](https://github.com/sxyazi/yazi/pull/3781)); Lua 5.5 ([#3633](https://github.com/sxyazi/yazi/pull/3633)) | CLI/plugin runtime |
| v26.5.6 | Dynamic Lua APIs for previewers ([#3891](https://github.com/sxyazi/yazi/pull/3891)) and open/openers ([#3901](https://github.com/sxyazi/yazi/pull/3901)) | plugins can be configured at runtime instead of via config rules |
| v26.8.15 | Dynamic Lua API for preloader/spotter/**fetcher** ([#4235](https://github.com/sxyazi/yazi/pull/4235)); package hashes made line-ending insensitive ([#4064](https://github.com/sxyazi/yazi/pull/4064)) | config rules become optional; hash stability |
| v26.9.1 | "Materialize Git symlinks for consistent hashes" ([#4276](https://github.com/sxyazi/yazi/pull/4276)) | affects `ya pkg` hashes for repos containing symlinks |
| Unreleased (already in the deployed commit) | **`search` action superseded by `plugin rg` / `plugin fd`** ([#4335](https://github.com/sxyazi/yazi/pull/4335)); `escape --search` → `escape --view`; legacy Git-symlink compat in the package cache ([#4319](https://github.com/sxyazi/yazi/pull/4319)) | see §8 |

## 8. What this means for our config

> **State caveat.** This section describes the repo as of 2026-09-17, before the migration in §11 landed. Where §8 disagrees with the tree you see now, the tree is newer.

### 8.1 `yazi/package.toml` — schema is current and *accurate*, but redundant and unusable as-is on the deployed machine

- The file **parses correctly** and matches `ya pkg`'s canonical serialization byte-for-byte. Observed:
  - `YAZI_CONFIG_HOME=/tmp/pkgtest/conf XDG_CACHE_HOME=/tmp/pkgtest/cache ya pkg list` → prints `yazi-rs/plugins:git (6af9bf2)`, `hankertrix/augment-command (6269d41)`, `iynaix/time-travel (aaec6e2)`, `Flavors:` (empty) — exit 0.
  - A full `ya pkg install` into that scratch copy cloned/checked out all three pinned revs, re-deployed them, left `package.toml` **unchanged**, and `diff -rq` against `yazi/` reports **no differences at all** — i.e. our vendored plugin trees are exactly what the pins produce (files written read-only by `ya pkg` vs 0644 in git; content identical).
  - So `package.toml` is a correct *lockfile* of the vendored state, and the 3 revs are not stale relative to the vendored trees.
- It is **redundant**: the same trees are committed under `yazi/plugins/`, and the loader never reads `package.toml`.
- It is **dangerous to use in place**, because of how the machine is actually deployed: `~/.config/yazi/{yazi.toml,keymap.toml,init.lua,package.toml}` are symlinks into `/nix/store/9jcggy0q5246xsm8k9skgk0wszfp92im-hm_yazi/` and `~/.config/yazi/plugins/*` are symlinks into the read-only home-manager store path. `ya pkg add/install/upgrade/delete` all end with `Package::save()` writing `package.toml` — writing through that symlink hits the read-only store and fails; and `copy_and_seal()` would first *replace* the home-manager symlinks in `plugins/<name>.yazi/` with real, non-Nix files (the plugin dir itself is a writable real directory), producing state home-manager does not own. **Recommendation: do not run `ya pkg` against this deployment.** If we ever want `ya pkg`, the config dir must become writable and non-store-managed (e.g. `mkOutOfStoreSymlink`, or drop the `home.file` copy and let `ya pkg` own `~/.config/yazi`).
- Keep/rewrite decision: keeping it as documentation is harmless; if kept, note it must be updated by hand whenever a vendored plugin is bumped, otherwise `ya pkg` operations would abort on a hash mismatch (§2.2).

### 8.2 `yazi/yazi.toml` — one dead block, and it is dead *because of the two schema changes in §7*

```toml
[plugin]
prefetchers = [
	{ url = "*", cond = "!mime", run = "mime", prio = "high" },
]
```

Three independent problems, each fatal on its own:
1. `prefetchers` is not a valid key (the valid ones are `fetchers`/`prepend_fetchers`/`append_fetchers`) and never was in any version checked. Unknown keys are silently ignored → **this rule does nothing at all today** (`IgnoredAny`, §5.4).
2. `cond` is not a fetcher field in any version (the historical name was `if`, removed before v25.2.7; the current schema has no condition field at all).
3. `run = "mime"` names a builtin that is now an empty tombstone (§4.2) — even a correctly-formed rule would not fetch MIME types.

**Fix:** delete the `prefetchers` block entirely. It is unnecessary: the built-in default `[plugin] fetchers` already covers MIME for directories, local files, trash and remote files, and user config only *prepends/appends* to those defaults.

Also in this file:
- The two `[[plugin.prepend_fetchers]]` rules for `git` are **valid** at this commit (`url` + `run` + `group`); the extra `id = "git"` key is now ignored (`#[serde(skip)]`) but harmless. Optional cleanup: drop `id`, since `group` supersedes it.
- The `prepend_previewers` blocks naming `run = "ouch"` are schema-valid, but see §8.4.
- The commented-out `mime-ext` block (`id`/`if`/`name`) is correctly commented — `name` and `if` are dead keys, so it must not be resurrected as written.

### 8.3 The stale `mime.yazi` submodule — answered definitively

- `.gitmodules` has `[submodule "yazi/plugins/mime.yazi"] path = yazi/plugins/mime.yazi url = https://github.com/DreamMaoMao/mime.yazi.git`, but `git ls-files -s yazi/plugins` contains **no gitlink (160000) for `mime.yazi`** — the entry is unreferenced, and no directory exists. So it is already inert for git and invisible to yazi.
- **It is not needed and must not be re-added.** `mime` is a builtin name (empty tombstone at this commit), the loader would never read `plugins/mime.yazi/`, and MIME typing is already handled by the built-in `mime.local`/`mime.dir`/`mime.trash`/`mime.remote` fetchers.
- Safe cleanup (does not affect yazi): delete the `[submodule "yazi/plugins/mime.yazi"]` stanza from `.gitmodules`. The matching `prefetchers` block in `yazi.toml` should go with it (§8.2).

### 8.4 `yazi/plugins/ouch.yazi` — the real gap on the deployed machine

The submodule exists in git (`160000 8e70ec74…`) but is **absent from the deployed config**: the store copy `/nix/store/9jcggy0q5246xsm8k9skgk0wszfp92im-hm_yazi/plugins/` contains only `augment-command.yazi`, `git.yazi`, `time-travel.yazi` (verified by listing the store path and `~/.config/yazi/plugins/`). Since `yazi.toml` prepends three `run = "ouch"` archive previewers, those rules currently reference a plugin that isn't deployed. Likely mechanism: the flake/Nix source copy only includes git-tracked files, and submodule contents are not tracked by the parent repo (consistent with the other two plugins being present as regular tracked files). *Marked as likely, not proven* — what would settle it: inspecting the evaluated flake source path / `home.file` derivation inputs. Options: vendor `ouch.yazi` as regular tracked files (matching the other three plugins), or drop the ouch previewer rules.

### 8.5 Adjacent staleness worth fixing while we're here (found while verifying §7)

- `yazi/keymap.toml`: `run = 'search rg'` (the `R` binding) is **inert** at the deployed commit — the `search` action no longer exists: there is no `Search` variant in the action registry ([`yazi-parser/src/spark/spark.rs`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-parser/src/spark/spark.rs)), no `yazi-actor/src/mgr/search.rs`, no `yazi-parser/src/mgr/search.rs`, and the mgr-layer dispatcher's fallback is a silent no-op (`_ => succ!()`, [`yazi-fm/src/executor.rs#L65-L161`](https://github.com/sxyazi/yazi/blob/a228e69df26b9b9a68de6805099c471af5a86719/yazi-fm/src/executor.rs#L65-L161)). Upstream's default keymap now uses `plugin rg` / `plugin fd` (`yazi-config/preset/keymap-default.toml#L85-L86`). Fix: `run = "plugin rg"`.
- `yazi/keymap.toml`: `run = "plugin time-travel --args=prev"` (×3) uses the pre-25.2.7 `--args=` form (deprecated in [#2299](https://github.com/sxyazi/yazi/pull/2299)). `Cmd::parse_args` turns `--args=prev` into named arg `args="prev"`, while the vendored plugin reads `job.args[1]` (`yazi/plugins/time-travel.yazi/main.lua`, `local action = job.args[1]`) → "Invalid action: nil". The plugin's own README at the pinned rev documents the current form: `run = "plugin time-travel prev"`. Fix: drop `--args=`.
- `[[mgr.prepend_keymap]]` (not the deprecated `[manager]`) is already correct.
- `yazi/init.lua`'s `require("git"):setup()` / `require("augment-command"):setup{…}` are fine: both names are non-builtin, so they load from our vendored dirs.

### 8.6 Summary table

| File | Change needed | Why |
| --- | --- | --- |
| `yazi/yazi.toml` | delete the `[plugin] prefetchers = [...]` block | invalid key (silently ignored), dead `cond` field, tombstoned `run = "mime"` |
| `yazi/yazi.toml` | optional: drop now-ignored `id = "git"` from the two `prepend_fetchers` rules | `id` → `group` ([#3943](https://github.com/sxyazi/yazi/pull/3943)) |
| `.gitmodules` | delete the `yazi/plugins/mime.yazi` stanza | no gitlink in the index; `mime` is a builtin, no plugin dir wanted |
| `yazi/plugins/ouch.yazi` | vendor as regular tracked files, or drop the ouch rules | submodule content does not reach the deployed (Nix) config |
| `yazi/keymap.toml` | `search rg` → `plugin rg`; `plugin time-travel --args=X` → `plugin time-travel X` | `search` action removed ([#4335](https://github.com/sxyazi/yazi/pull/4335)); `--args` form obsolete |
| `yazi/package.toml` | keep as-is (valid, accurate) or delete as redundant; do **not** run `ya pkg` against the store-managed config dir | §8.1 |
| `home-manager/programs/yazi.nix` | no change required for a vendored setup; change only if we want `ya pkg` to own the config dir | §6, §8.1 |

## 9. Unresolved / what would settle it

1. **Exact runtime failure of `run = "mime"` and of shadowing a builtin name.** Source reading says the empty chunk can't satisfy `Loader::load_new`'s `Table` expectation and that builtin names short-circuit the filesystem lookup, but the TUI could not be executed here (sandbox denies PTY: `script: openpty: Operation not permitted`). Moot after §11, which deletes the invalid `prefetchers` block; to settle the shadowing question anyway, run yazi with `YAZI_LOG=debug` in a real terminal with a `plugins/mime.yazi/` dir present and read `~/.local/state/yazi/yazi.log`.
2. **Why `ouch.yazi` is missing from the deployed config** — resolved in §11: the home-manager copy of `.config/yazi/plugins/` held only the three tracked plugins, because submodule contents are never part of Nix's copy of the repo.
3. **Whether upstream considers a read-only config dir supported.** No upstream statement exists in docs, CHANGELOG or PRs that I could find; the Nix home-manager template is the only (implicit) endorsement of vendoring.

## 10. Evidence log (commands actually run, and what they showed)

Local, first-party:
- `ya --version`, `yazi --version` → `26.9.1 (a228e69 2026-09-16)`.
- `ya pkg --help`, `ya pkg {add,delete,install,list,upgrade} --help` → command set & flags in §1 (no `verify`).
- `ya pack --help` / `ya pack` → `error: unrecognized subcommand 'pack'`, exit 2.
- `YAZI_CONFIG_HOME=/tmp/pkgtest/conf XDG_CACHE_HOME=/tmp/pkgtest/cache ya pkg list` → parsed our `package.toml`, exit 0.
- Same env + `ya pkg install` → cloned the three pinned revs, deployed, `Done!` ×3, exit 0; afterwards `diff -rq` between `/tmp/pkgtest/conf` and `yazi/` → **no differences**; `package.toml` unchanged.
- `git ls-files -s yazi/plugins` → `160000 … yazi/plugins/ouch.yazi` present, **no** gitlink for `mime.yazi`.
- `ls -l ~/.config/yazi` and store listings → config files are store symlinks; `plugins/` contains only the 3 regular tracked plugins, **no `ouch.yazi`**.
- `script -q /dev/null env YAZI_CONFIG_HOME=… yazi` → `script: openpty: Operation not permitted` (PTY denied; documented as a limitation, not retried).

Upstream, at commit `a228e69df26b9b9a68de6805099c471af5a86719` (shallow clone at `/tmp/yz/repo`, plus `raw.githubusercontent.com` fetches at tags `v0.1.6`, `v0.2.5`, `v0.3.3`, `v0.4.0`, `v25.2.7`, `v25.5.28`, `v25.5.31`, `v25.12.29`, `v26.1.22`, `v26.5.6`, `v26.8.15`): all source citations above; docs clone at `/tmp/yz/docs` (`yazi-rs/yazi-rs.github.io`).

---

## 11. Implemented state (supersedes §8's state caveat)

The migration §8 calls for has since landed; its recommendations are now history. The tree:

- `yazi/yazi.toml`: dead `[plugin] prefetchers` block deleted; `id = "git"` dropped from the two
  `[[plugin.prepend_fetchers]]` entries (it is `#[serde(skip)]` in `Fetcher`); the six
  `run = "ouch"` previewers deleted (builtin `archive` covers them); all `[opener]` `$@`/`$1`/`%*`/`%1`
  migrated to the splatter placeholders (`%s`, `%s1`).
- `yazi/keymap.toml`: `run = 'search rg'` → `run = 'plugin rg'`; the three
  `plugin time-travel --args=X` → positional `plugin time-travel X`.
- `yazi/init.lua` and `yazi/package.toml` deleted; `yazi/plugins/**` (three vendored plugins plus
  the `ouch.yazi` gitlink) deleted; both `yazi/plugins/*` stanzas removed from `.gitmodules`
  (only `tmux` and `qemu-script` remain).
- `flake.nix`: three `flake = false` inputs pinned to the revisions the old `package.toml`
  recorded — `yazi-plugin-git` (`yazi-rs/plugins`, full SHA `6af9bf23be808db4a86e89d2fc32d488dcafdd34`,
  subdir `git.yazi`), `yazi-plugin-augment-command` (`hankertrix/augment-command.yazi`
  @ `6269d417…`, repo renamed from `augment-command`), `yazi-plugin-time-travel`
  (`iynaix/time-travel.yazi` @ `aaec6e26…`, repo renamed from `time-travel`).
- `home-manager/programs/yazi.nix`: now uses home-manager's own `programs.yazi` module —
  `plugins.<name>.package` + `setup`/`settings` — instead of `home.file … recursive = true` over the
  whole `yazi/` directory; `yazi.toml`/`keymap.toml` are still the hand-written repo files, linked
  individually via `xdg.configFile`. Shell integrations stay off (`shellWrapperName = "yy"` kept to
  silence the 26.05 rename warning).

Verified by evaluation only (no switch was run): `nix flake lock` added the three inputs with
narHashes; `nix build .#homeConfigurations."chin39@macos".config.programs.yazi.plugins.git.package`
produced a `git.yazi` store path containing `main.lua`/`types.lua`; the two other plugin packages
resolve to store paths containing `main.lua`; the generated
`~/.config/yazi/init.lua` contains exactly `require("augment-command"):setup({…10 settings…})` and
`require("git"):setup()`; `config.warnings` is `[ ]`. Deploying is still a human step:
`home-manager switch --flake .#chin39@macos` (plus `darwin-rebuild switch --flake .#macos` for the
system side).
