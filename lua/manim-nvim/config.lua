---@class ManimConfig
---@field terminal_position "right"|"bottom" Terminal split position
---@field terminal_size number Terminal size as fraction of screen (0.0-1.0)
---@field manim_cmd string Command to run manim ("manimgl" or "manim")
---@field default_flags string Additional flags to pass to manim command
---@field keymaps ManimKeymaps|false Keymap configuration, or false to disable all

---@class ManimKeymaps
---@field start_session string|false Keymap to start session
---@field stop_session string|false Keymap to stop session
---@field run_line string|false Keymap to run current line
---@field run_selection string|false Keymap to run visual selection
---@field focus_terminal string|false Keymap to focus terminal
---@field start_watcher string|false Keymap to start file watcher
---@field stop_watcher string|false Keymap to stop file watcher

local M = {}

---@type ManimConfig
M.defaults = {
	terminal_position = "right",
	terminal_size = 0.4,
	manim_cmd = "manimgl",
	default_flags = "",
	keymaps = {
		start_session = "<leader>mo",
		stop_session = "<leader>mc",
		run_line = "<leader>mr",
		run_selection = "<leader>mr",
		focus_terminal = "<leader>mf",
		start_watcher = "<leader>mw",
		stop_watcher = "<leader>ms",
	},
}

---@type ManimConfig
M.options = vim.deepcopy(M.defaults)

---Validate configuration options
---@param opts ManimConfig?
---@return boolean valid
---@return string? error_message
function M.validate(opts)
	if not opts then
		return true
	end

	if opts.terminal_position and opts.terminal_position ~= "right" and opts.terminal_position ~= "bottom" then
		return false, "terminal_position must be 'right' or 'bottom'"
	end

	if opts.terminal_size then
		if type(opts.terminal_size) ~= "number" then
			return false, "terminal_size must be a number"
		end
		if opts.terminal_size <= 0 or opts.terminal_size >= 1 then
			return false, "terminal_size must be between 0 and 1"
		end
	end

	if opts.manim_cmd and type(opts.manim_cmd) ~= "string" then
		return false, "manim_cmd must be a string"
	end

	if opts.default_flags and type(opts.default_flags) ~= "string" then
		return false, "default_flags must be a string"
	end

	return true
end

---Setup configuration with user options
---@param opts ManimConfig?
function M.setup(opts)
	local valid, err = M.validate(opts)
	if not valid then
		vim.notify("[manim-nvim] Invalid config: " .. err, vim.log.levels.ERROR)
		return
	end

	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---Get current configuration
---@return ManimConfig
function M.get()
	return M.options
end

return M
