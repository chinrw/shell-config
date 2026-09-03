-- Shared by the macOS, Linux and Windows hosts. Deploy by copying this
-- directory to ~/.config/wezterm/ (not wired through home-manager).
-- Per-host taste goes in an untracked local.lua there, see local.lua.example.
local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- package.path only covers ~/.config/wezterm. Add the directory this file was
-- loaded from so `wezterm --config-file <repo>/wezterm/wezterm.lua` resolves
-- tab_title and local as well.
package.path = wezterm.config_file:gsub("[^/\\]+$", "?.lua") .. ";" .. package.path

local triple = wezterm.target_triple
local is_macos = triple:find("apple%-darwin") ~= nil
local is_windows = triple:find("windows") ~= nil
local is_wayland = os.getenv("WAYLAND_DISPLAY") ~= nil

---------------------------------------------------------------------------
-- Fonts
-- Fallback entries that are not installed are skipped silently, so one list
-- serves every host. Only the CJK face is per platform: without an explicit
-- one the implicit system fallback picks an unpredictable face.
-- See what resolves with: wezterm ls-fonts --list-system | grep -i meslo
---------------------------------------------------------------------------
local cjk_fonts = is_macos and { "PingFang SC" }
    or { "Noto Sans CJK JP", "Noto Sans CJK SC", "Noto Sans CJK TC", "WenQuanYi Micro Hei" }
local italic_family = is_windows and "Iosevka NF" or "MesloLGM Nerd Font"

local function font_with_fallback(spec)
    local names = { spec, "MesloLGM Nerd Font", "mini-file-icons", "SauceCodePro Nerd Font" }
    for _, name in ipairs(cjk_fonts) do
        table.insert(names, name)
    end
    return wezterm.font_with_fallback(names)
end

config.font = font_with_fallback({ family = "MesloLGM Nerd Font", harfbuzz_features = { "zero" } })
config.font_rules = {
    {
        intensity = "Bold",
        font = font_with_fallback({
            family = "MesloLGM Nerd Font",
            harfbuzz_features = { "zero" },
            weight = "Medium",
        }),
    },
    {
        intensity = "Bold",
        italic = true,
        font = font_with_fallback({ family = italic_family, weight = "Medium", italic = true }),
    },
    {
        italic = true,
        font = font_with_fallback({ family = italic_family, weight = "Regular", italic = true }),
    },
}
config.font_size = is_macos and 15 or is_windows and 11 or 12
config.bold_brightens_ansi_colors = false
config.warn_about_missing_glyphs = false
-- bidi_enabled stays at the default (off): experimental, and it adds a
-- per-line shaping cost.

---------------------------------------------------------------------------
-- Time-based color scheme
-- Entries are { start_hour, scheme } in ascending order. The last entry also
-- covers the hours before the first start, i.e. it wraps past midnight.
---------------------------------------------------------------------------
local schedule = is_windows
    and { { 1, "tokyonight_night" }, { 21, "kanagawabones" } }
    or { { 9, "tokyonight" }, { 17, "Catppuccin Mocha" }, { 22, "Rosé Pine (base16)" } }

local function scheme_for_hour(hour)
    local scheme = nil
    for _, entry in ipairs(schedule) do
        if entry[1] <= hour then
            scheme = entry[2]
        end
    end
    return scheme or schedule[#schedule][2]
end

local function current_scheme()
    return scheme_for_hour(os.date("*t").hour)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------
-- WebGpu misbehaved under Wayland (git log: "Fix wezterm wayland issue") and
-- Windows keeps wezterm's default; macOS and X11 use it.
if not is_windows and not is_wayland then
    config.front_end = "WebGpu"
end
-- 1 fps turns cursor and bell easing into plain transitions; cheap on the GPU.
config.animation_fps = 1
-- macOS: the FSEvents watcher costs more than it is worth, reload with
-- CMD+SHIFT+R instead. Elsewhere the watcher is cheap, and niri binds
-- Mod+Shift+R itself, so auto reload stays on.
config.automatically_reload_config = not is_macos

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
config.selection_word_boundary = " \t\n{}[]()\"'`,;:│=&!%"
if is_macos then
    -- Tahoe recomputes the shadow every frame for non-opaque windows
    -- (wezterm/wezterm#7271); without it GPU power drops from ~20W to ~0.2W.
    config.window_decorations = "TITLE | RESIZE | MACOS_FORCE_DISABLE_SHADOW"
end
if is_windows then
    config.window_decorations = "RESIZE"
    config.window_background_opacity = 0.95
    config.use_fancy_tab_bar = false -- tab_title.lua styles the retro bar
    config.default_prog = { "powershell.exe" }
    config.wsl_domains = {
        { name = "WSL:fedora", distribution = "fedora", default_cwd = "/home/chin39" },
    }
    require("tab_title")
else
    config.hide_tab_bar_if_only_one_tab = true
    config.initial_cols = 128
    config.initial_rows = 32
    config.line_height = 1.1
    config.window_padding = { left = "1cell", right = "1cell", top = "0.5cell", bottom = "0.5cell" }
end

---------------------------------------------------------------------------
-- Keys and mouse
---------------------------------------------------------------------------
local keys = {
    { key = "{", mods = "SHIFT|ALT", action = act.MoveTabRelative(-1) },
    { key = "}", mods = "SHIFT|ALT", action = act.MoveTabRelative(1) },
    { key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
}
for i = 1, 8 do
    table.insert(keys, { key = tostring(i), mods = "ALT", action = act.ActivateTab(i - 1) })
end
config.keys = keys

config.mouse_bindings = {
    -- Left-click release would otherwise complete the selection and copy it.
    { event = { Up = { streak = 1, button = "Left" } }, mods = "NONE", action = act.Nop },
}

---------------------------------------------------------------------------
-- Per-host overrides
---------------------------------------------------------------------------
local has_local, host = pcall(require, "local")
if has_local then
    for k, v in pairs(host) do
        config[k] = v
    end
elseif not tostring(host):find("not found", 1, true) then
    wezterm.log_error("local.lua failed to load: " .. tostring(host))
end
local fixed_scheme = has_local and host.color_scheme or nil

---------------------------------------------------------------------------
-- Runtime overrides: theme and max_fps
-- Applied through set_config_overrides from update-status. A full reload
-- would re-evaluate everything, and wezterm.gui.screens() only works on the
-- gui thread, not while this file is evaluated. max_fps follows the screen
-- the window is on; Wayland ignores it and paces frames from the compositor.
---------------------------------------------------------------------------
local function screen_max_fps()
    local ok, screens = pcall(wezterm.gui.screens)
    return ok and screens.active.max_fps or nil
end

config.color_scheme = fixed_scheme or current_scheme()
config.status_update_interval = 60000

wezterm.on("update-status", function(window, _pane)
    local current = window:get_config_overrides() or {}
    local wanted = { color_scheme = fixed_scheme or current_scheme(), max_fps = screen_max_fps() }
    local next_overrides = {}
    local changed = false
    for k, v in pairs(current) do
        next_overrides[k] = v
    end
    for k, v in pairs(wanted) do
        if v ~= nil and current[k] ~= v then
            next_overrides[k] = v
            changed = true
        end
    end
    if changed then
        window:set_config_overrides(next_overrides)
    end
end)

return config
