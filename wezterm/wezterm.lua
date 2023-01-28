local wezterm = require("wezterm")

local scheme = wezterm.get_builtin_color_schemes()["tokyonight"]

local function scheme_for_appearance(appearance)
	if appearance:find("Dark") then
		return "tokyonight"
		-- return "Catppuccin Mocha"
	else
		return "Catppuccin Latte"
	end
end

return {
	-- ...your existing config
	font = wezterm.font("MesloLGM Nerd Font"),
	font_size = 14.0,
	selection_word_boundary = " \t\n{}[]()\"'`,;:│=&!%",
	window_padding = {
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
	},
	-- use_fancy_tab_bar = false,
	-- colors = {
	-- 	tab_bar = {
	-- 		background = scheme.background,
	-- 		new_tab = { bg_color = "#2e3440", fg_color = scheme.ansi[8], intensity = "Bold" },
	-- 		new_tab_hover = { bg_color = scheme.ansi[1], fg_color = scheme.brights[8], intensity = "Bold" },
	-- 	},
	-- },
	color_scheme = scheme_for_appearance(wezterm.gui.get_appearance()),
}
