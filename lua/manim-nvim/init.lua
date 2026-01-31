---@mod manim-nvim Interactive Manim development for Neovim
---@brief [[
---manim-nvim provides an interactive workflow for developing Manim animations
---in Neovim, inspired by the 3Blue1Brown workflow.
---
---Features:
---- Interactive terminal session with manimgl
---- Send code from editor to running session
---- File watcher for automatic recompilation
---
---Quick start:
---  require('manim-nvim').setup()
---  -- Open a Python file with a Manim scene
---  -- :ManimStart to begin interactive session
---  -- <leader>mr to run current line
---@brief ]]

local M = {}

---@type boolean
local is_setup = false

---Setup manim-nvim with user configuration
---@param opts ManimConfig? Configuration options
---@usage [[
---require('manim-nvim').setup({
---  terminal_position = 'right',  -- 'right' or 'bottom'
---  terminal_size = 0.4,          -- 40% of screen
---  manim_cmd = 'manimgl',        -- or 'manim' for community version
---  default_flags = '',           -- additional flags
---  keymaps = {
---    start_session = '<leader>mo',
---    stop_session = '<leader>mc',
---    run_line = '<leader>mr',
---    run_selection = '<leader>mr',
---    focus_terminal = '<leader>mf',
---    start_watcher = '<leader>mw',
---    stop_watcher = '<leader>ms',
---  },
---})
---@usage ]]
function M.setup(opts)
	if is_setup then
		vim.notify("[manim-nvim] Already setup, skipping", vim.log.levels.DEBUG)
		return
	end

	-- Setup configuration
	local config = require("manim-nvim.config")
	config.setup(opts)

	-- Setup keymaps
	M._setup_keymaps()

	is_setup = true
end

---Setup keymaps based on configuration
---@private
function M._setup_keymaps()
	local config = require("manim-nvim.config")
	local keymaps = config.get().keymaps

	if keymaps == false then
		return
	end

	local terminal = require("manim-nvim.terminal")

	if keymaps.start_session then
		vim.keymap.set("n", keymaps.start_session, terminal.start_session, { desc = "[Manim] Start session" })
	end

	if keymaps.stop_session then
		vim.keymap.set("n", keymaps.stop_session, terminal.stop_session, { desc = "[Manim] Stop session" })
	end

	if keymaps.run_line then
		vim.keymap.set("n", keymaps.run_line, terminal.run_line, { desc = "[Manim] Run current line" })
	end

	if keymaps.run_selection then
		vim.keymap.set("v", keymaps.run_selection, function()
			-- Exit visual mode first, then run selection
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
			terminal.run_selection()
		end, { desc = "[Manim] Run selection" })
	end

	if keymaps.focus_terminal then
		vim.keymap.set("n", keymaps.focus_terminal, terminal.focus_terminal, { desc = "[Manim] Focus terminal" })
	end

	-- Watcher keymaps (only if plenary is available)
	local has_plenary, _ = pcall(require, "plenary")
	if has_plenary then
		local watcher = require("manim-nvim.watcher")

		if keymaps.start_watcher then
			vim.keymap.set("n", keymaps.start_watcher, watcher.start, { desc = "[Manim] Start watcher" })
		end

		if keymaps.stop_watcher then
			vim.keymap.set("n", keymaps.stop_watcher, watcher.stop, { desc = "[Manim] Stop watcher" })
		end
	end
end

-- Re-export submodule functions for convenience
-- These allow users to call require('manim-nvim').start_session() directly

---Start interactive manimgl session
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.start_session(file, scene)
	return require("manim-nvim.terminal").start_session(file, scene)
end

---Stop the current session
---@return boolean success
function M.stop_session()
	return require("manim-nvim.terminal").stop_session()
end

---Restart the session with the same scene
---@return boolean success
function M.restart_session()
	return require("manim-nvim.terminal").restart_session()
end

---Focus the terminal window
---@return boolean success
function M.focus_terminal()
	return require("manim-nvim.terminal").focus_terminal()
end

---Send text to terminal
---@param text string Text to send
---@return boolean success
function M.send_to_terminal(text)
	return require("manim-nvim.terminal").send_to_terminal(text)
end

---Run current line in terminal
---@return boolean success
function M.run_line()
	return require("manim-nvim.terminal").run_line()
end

---Run visual selection in terminal
---@return boolean success
function M.run_selection()
	return require("manim-nvim.terminal").run_selection()
end

---Start file watcher
---@param file string? File to watch (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.start_watcher(file, scene)
	local has_plenary, _ = pcall(require, "plenary")
	if not has_plenary then
		vim.notify("[manim-nvim] Watcher requires plenary.nvim", vim.log.levels.ERROR)
		return false
	end
	return require("manim-nvim.watcher").start(file, scene)
end

---Stop file watcher
---@return boolean success
function M.stop_watcher()
	local has_plenary, _ = pcall(require, "plenary")
	if not has_plenary then
		vim.notify("[manim-nvim] Watcher requires plenary.nvim", vim.log.levels.ERROR)
		return false
	end
	return require("manim-nvim.watcher").stop()
end

return M
