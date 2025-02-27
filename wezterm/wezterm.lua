local wezterm = require("wezterm")

-- local launch_menu = {}
-- Reload the configuration every ten minutes

-- A helper function for my fallback fonts
local function font_with_fallback(name, params)
	local names = {
		name,
		"MesloLGM Nerd Font",
		"mini-file-icons",
		"SauceCodePro Nerd Font",
		"Noto Sans CJK JP",
		"Noto Sans CJK SC",
		"Noto Sans CJK TC",
		"WenQuanYi Micro Hei",
	}
	return wezterm.font_with_fallback(names, params)
end

-- Reload the configuration every ten minutes
wezterm.time.call_after(600, function()
	wezterm.reload_configuration()
end)

local padding = {
	left = "1cell",
	right = "1cell",
	top = "0.5cell",
	bottom = "0.5cell",
}

local function get_theme()
	local _time = os.date("*t")
	if _time.hour >= 22 or _time.hour < 9 then
		return "Rosé Pine (base16)"
	elseif _time.hour >= 9 and _time.hour < 17 then
		return "tokyonight"
	elseif _time.hour >= 17 and _time.hour < 22 then
		return "Catppuccin Mocha"
	end
end

local gpus = wezterm.gui.enumerate_gpus()


local act = wezterm.action
local mykeys = {}
for i = 1, 8 do
	-- ALT + number to activate that tab
	table.insert(mykeys, {
		key = tostring(i),
		mods = "ALT",
		action = act.ActivateTab(i - 1),
	})
end
table.insert(mykeys, { key = "{", mods = "SHIFT|ALT", action = act.MoveTabRelative(-1) })
table.insert(mykeys, { key = "}", mods = "SHIFT|ALT", action = act.MoveTabRelative(1) })

local config = {
	bidi_enabled = true,
	bidi_direction = "AutoLeftToRight",
	color_scheme = get_theme(),
	-- color_scheme = "tokyonight",
	font = font_with_fallback({
		family = "MesloLGM Nerd Font",
		harfbuzz_features = {
			"zero",
		},
	}),
	mouse_bindings = {
		-- Disable left drag
		{
			event = { Up = { streak = 1, button = "Left" } },
			mods = "NONE",
			action = "Nop",
		},
	},

	keys = mykeys,

	font_rules = {
		{
			intensity = "Bold",
			font = font_with_fallback({
				family = "MesloLGM Nerd Font",
				harfbuzz_features = {
					"zero",
				},
				weight = "Medium",
			}),
		},
		{
			italic = true,
			intensity = "Bold",
			font = font_with_fallback({
				family = "MesloLGM Nerd Font",
				-- family = "Dank Mono",
				weight = "Medium",
				italic = true,
			}),
		},
		{
			italic = true,
			font = font_with_fallback({
				-- family = "Dank Mono",
				family = "MesloLGM Nerd Font",
				weight = "Regular",
				italic = true,
			}),
		},
	},
	initial_cols = 128,
	initial_rows = 32,
	-- use_dead_keys = false,
	-- window_decorations = "RESIZE",
	hide_tab_bar_if_only_one_tab = true,
	selection_word_boundary = " \t\n{}[]()\"'`,;:│=&!%",
	window_padding = padding,
	line_height = 1.1,
	font_size = 12,
	-- window_background_opacity = 0.95,
	bold_brightens_ansi_colors = false,
  warn_about_missing_glyphs = false,
	-- swap_backspace_and_delete = false,
	-- term = "wezterm",
	-- freetype_load_target = "Light",
}

-- config.webgpu_preferred_adapter = gpus[2]
-- config.front_end = 'WebGpu'

return config
