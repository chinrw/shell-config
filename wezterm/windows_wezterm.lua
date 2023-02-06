local wezterm = require("wezterm")

-- local launch_menu = {}

-- A helper function for my fallback fonts
local function font_with_fallback(name, params)
	local names = { name, "mini-file-icons", "MesloLGM Nerd Font", "SauceCodePro Nerd Font" }
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
	if _time.hour >= 1 and _time.hour < 9 then
		return "tokyonight_night"
	elseif _time.hour >= 9 and _time.hour < 17 then
		return "tokyonight_night"
	elseif _time.hour >= 17 and _time.hour < 21 then
		return "tokyonight_night"
	elseif _time.hour >= 21 and _time.hour < 24 or _time.hour >= 0 and _time.hour < 1 then
		return "kanagawabones"
	end
end


local act = wezterm.action



local mykeys = {
	      	{ key = '{', mods = 'SHIFT|ALT', action = act.MoveTabRelative(-1) },
	      	  	{ key = '}', mods = 'SHIFT|ALT', action = act.MoveTabRelative(1) },


}
for i = 1, 8 do
  -- ALT + number to activate that tab
  table.insert(mykeys, {
    key = tostring(i),
    mods = 'ALT',
    action = act.ActivateTab(i - 1),
  })
end

function basename(s)
  return string.gsub(s, '(.*[/\\])(.*)', '%2')
end

local SOLID_LEFT_ARROW = utf8.char(0xe0ba)
local SOLID_LEFT_MOST = utf8.char(0x2588)
local SOLID_RIGHT_ARROW = utf8.char(0xe0bc)

local ADMIN_ICON = utf8.char(0xf49c)

local CMD_ICON = utf8.char(0xe62a)
local NU_ICON = utf8.char(0xe7a8)
local PS_ICON = utf8.char(0xe70f)
local ELV_ICON = utf8.char(0xfc6f)
local WSL_ICON = utf8.char(0xf83c)
local YORI_ICON = utf8.char(0xf1d4)
local NYA_ICON = utf8.char(0xf61a)

local VIM_ICON = utf8.char(0xe62b)
local PAGER_ICON = utf8.char(0xf718)
local FUZZY_ICON = utf8.char(0xf0b0)
local HOURGLASS_ICON = utf8.char(0xf252)
local SUNGLASS_ICON = utf8.char(0xf9df)

local PYTHON_ICON = utf8.char(0xf820)
local NODE_ICON = utf8.char(0xe74e)
local DENO_ICON = utf8.char(0xe628)
local LAMBDA_ICON = utf8.char(0xfb26)

local SUP_IDX = {"¹","²","³","⁴","⁵","⁶","⁷","⁸","⁹","¹⁰",
                 "¹¹","¹²","¹³","¹⁴","¹⁵","¹⁶","¹⁷","¹⁸","¹⁹","²⁰"}
local SUB_IDX = {"₁","₂","₃","₄","₅","₆","₇","₈","₉","₁₀",
                 "₁₁","₁₂","₁₃","₁₄","₁₅","₁₆","₁₇","₁₈","₁₉","₂₀"}


wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local edge_background = "#121212"
  local background = "#4E4E4E"
  local foreground = "#1C1B19"
  local dim_foreground = "#3A3A3A"

  if tab.is_active then
    background = "#FBB829"
    foreground = "#1C1B19"
  elseif hover then
    background = "#FF8700"
    foreground = "#1C1B19"
  end

  local edge_foreground = background
  local process_name = tab.active_pane.foreground_process_name
  local pane_title = tab.active_pane.title
  local exec_name = basename(process_name):gsub("%.exe$", "")
  local title_with_icon

  if exec_name == "nu" then
    title_with_icon = NU_ICON .. " NuShell"
  elseif exec_name == "powershell" then
    title_with_icon = PS_ICON .. " PS"
  elseif exec_name == "cmd" then
    title_with_icon = CMD_ICON .. " CMD"
  elseif exec_name == "elvish" then
    title_with_icon = ELV_ICON .. " Elvish"
  elseif exec_name == "wsl" or exec_name == "wslhost" then
    title_with_icon = WSL_ICON .. " WSL"
  elseif exec_name == "nyagos" then
    title_with_icon = NYA_ICON .. " " .. pane_title:gsub(".*: (.+) %- .+", "%1")
  elseif exec_name == "yori" then
    title_with_icon = YORI_ICON .. " " .. pane_title:gsub(" %- Yori", "")
  elseif exec_name == "nvim" then
    title_with_icon = VIM_ICON .. pane_title:gsub("^(%S+)%s+(%d+/%d+) %- nvim", " %2 %1")
  elseif exec_name == "bat" or exec_name == "less" or exec_name == "moar" then
    title_with_icon = PAGER_ICON .. " " .. exec_name:upper()
  elseif exec_name == "fzf" or exec_name == "hs" or exec_name == "peco" then
    title_with_icon = FUZZY_ICON .. " " .. exec_name:upper()
  elseif exec_name == "btm" or exec_name == "ntop" then
    title_with_icon = SUNGLASS_ICON .. " " .. exec_name:upper()
  elseif exec_name == "python" or exec_name == "hiss" then
    title_with_icon = PYTHON_ICON .. " " .. exec_name
  elseif exec_name == "node" then
    title_with_icon = NODE_ICON .. " " .. exec_name:upper()
  elseif exec_name == "deno" then
    title_with_icon = DENO_ICON .. " " .. exec_name:upper()
  elseif exec_name == "bb" or exec_name == "cmd-clj" or exec_name == "janet" or exec_name == "hy" then
    title_with_icon = LAMBDA_ICON .. " " .. exec_name:gsub("bb", "Babashka"):gsub("cmd%-clj", "Clojure")
  else
    title_with_icon = HOURGLASS_ICON .. " " .. exec_name
  end
  if pane_title:match("^Administrator: ") then
    title_with_icon = title_with_icon .. " " .. ADMIN_ICON
  end
  local left_arrow = SOLID_LEFT_ARROW
  if tab.tab_index == 0 then
    left_arrow = SOLID_LEFT_MOST
  end
  local id = SUB_IDX[tab.tab_index+1]
  local pid = SUP_IDX[tab.active_pane.pane_index+1]
  local title = " " .. wezterm.truncate_right(title_with_icon, max_width-6) .. " "

  return {
    {Attribute={Intensity="Bold"}},
    {Background={Color=edge_background}},
    {Foreground={Color=edge_foreground}},
    {Text=left_arrow},
    {Background={Color=background}},
    {Foreground={Color=foreground}},
    {Text=id},
    {Text=title},
    {Foreground={Color=dim_foreground}},
    {Text=pid},
    {Background={Color=edge_background}},
    {Foreground={Color=edge_foreground}},
    {Text=SOLID_RIGHT_ARROW},
    {Attribute={Intensity="Normal"}},
  }
end)
  

return {
	-- bidi_enabled = true,
	-- bidi_direction = "AutoLeftToRight",
  keys = mykeys,
  default_prog = { 'powershell.exe' },
  
  wsl_domains = {
    {
      name = 'WSL:fedora',
      distribution = 'fedora',
      -- username = "hunter",
      default_cwd = "/home/chin39"
      -- default_prog = {"fish"}
    },
  },
  -- default_domain = 'WSL:Gentoo-updated',
	color_scheme = get_theme(),
	font = font_with_fallback({
		family = "MesloLGM Nerd Font",
		harfbuzz_features = {
			"zero",
		},
	}),
	-- disable selected copy
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
				family = "Iosevka NF",
				-- family = "Dank Mono",
				weight = "Medium",
				italic = true,
			}),
		},
		{
			italic = true,
			font = font_with_fallback({
				-- family = "Dank Mono",
				family = "Iosevka NF",
				weight = "Regular",
				italic = true,
			}),
	},
	},
	-- initial_cols = 128,
	-- initial_rows = 32,
	-- use_dead_keys = false,
	window_decorations = "RESIZE",
	-- hide_tab_bar_if_only_one_tab = true,
	selection_word_boundary = " \t\n{}[]()\"'`,;:│=&!%",
	--- window_padding = padding,
	-- line_height = 1.25,
	font_size = 11,
	window_background_opacity = 0.95,
	bold_brightens_ansi_colors = false,
	enable_scroll_bar = false,
	use_fancy_tab_bar = false,

	-- allow_win32_input_mode = false
	-- swap_backspace_and_delete = false,
	-- freetype_load_target = "Light",
}


