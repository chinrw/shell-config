function Linemode:size_and_mtime()
	local year = os.date("%Y")
	local time = (self._file.cha.modified or 0) // 1

	if time > 0 and os.date("%Y", time) == year then
		time = os.date("%b %d %H:%M", time)
	else
		time = time and os.date("%b %d  %Y", time) or ""
	end

	local size = self._file:size()
	return ui.Line(string.format(" %s %s ", size and ya.readable_size(size) or "-", time))
end

require("git"):setup()
require("augment-command"):setup({
	prompt = false,
	default_item_group_for_prompt = "hovered",
	smart_enter = true,
	smart_paste = false,
	enter_archives = true,
	extract_retries = 1,
	must_have_hovered_item = true,
	skip_single_subdirectory_on_enter = true,
	skip_single_subdirectory_on_leave = true,
	ignore_hidden_items = false,
	wraparound_file_navigation = false,
	sort_directories_first = true,
})
