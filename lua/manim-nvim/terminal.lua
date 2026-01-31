---@class TerminalState
---@field bufnr number|nil Buffer number of terminal
---@field chan_id number|nil Channel ID for sending commands
---@field win_id number|nil Window ID of terminal

---@class SessionState
---@field terminal TerminalState Terminal state
---@field scene_name string|nil Current scene name
---@field file_path string|nil Current file path

local M = {}

local config = require("manim-nvim.config")

---@type SessionState
local state = {
	terminal = {
		bufnr = nil,
		chan_id = nil,
		win_id = nil,
	},
	scene_name = nil,
	file_path = nil,
}

---Check if terminal session is active
---@return boolean
function M.is_active()
	return state.terminal.chan_id ~= nil
end

---Get current session state (read-only copy)
---@return SessionState
function M.get_state()
	return vim.deepcopy(state)
end

---Open terminal with manimgl interactive session
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.start_session(file, scene)
	-- Close existing session if any
	if state.terminal.chan_id then
		M.stop_session()
	end

	file = file or vim.fn.expand("%:p")
	if file == "" then
		vim.notify("[manim-nvim] No file to run", vim.log.levels.ERROR)
		return false
	end

	scene = scene or vim.fn.input("Scene name: ")
	if scene == "" then
		vim.notify("[manim-nvim] Scene name required", vim.log.levels.WARN)
		return false
	end

	-- Store state
	state.file_path = file
	state.scene_name = scene

	-- Save the current window to return to later
	local original_win = vim.api.nvim_get_current_win()
	local cfg = config.get()

	-- Create split based on position setting
	if cfg.terminal_position == "bottom" then
		vim.cmd("botright new")
		vim.cmd("resize " .. math.floor(vim.o.lines * cfg.terminal_size))
	else
		vim.cmd("botright vnew")
		vim.cmd("vertical resize " .. math.floor(vim.o.columns * cfg.terminal_size))
	end

	-- Store window ID before termopen (buffer will change)
	state.terminal.win_id = vim.api.nvim_get_current_win()

	-- Build command
	local cmd = string.format("%s %s %s", cfg.manim_cmd, vim.fn.shellescape(file), vim.fn.shellescape(scene))
	if cfg.default_flags ~= "" then
		cmd = cmd .. " " .. cfg.default_flags
	end

	-- Start terminal with manimgl
	state.terminal.chan_id = vim.fn.termopen(cmd, {
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				if exit_code ~= 0 then
					vim.notify("[manim-nvim] Session exited with code: " .. exit_code, vim.log.levels.WARN)
				end
			end)
			state.terminal.chan_id = nil
			state.terminal.bufnr = nil
			state.terminal.win_id = nil
		end,
	})

	if state.terminal.chan_id == 0 then
		vim.notify("[manim-nvim] Failed to start terminal", vim.log.levels.ERROR)
		vim.cmd("close")
		return false
	end

	state.terminal.bufnr = vim.api.nvim_get_current_buf()

	-- Set buffer options for terminal
	vim.bo[state.terminal.bufnr].buflisted = false
	vim.api.nvim_buf_set_name(state.terminal.bufnr, "manim://" .. scene)

	-- Return focus to original code window
	vim.api.nvim_set_current_win(original_win)

	vim.notify("[manim-nvim] Session started: " .. scene, vim.log.levels.INFO)
	return true
end

---Stop the current session
---@return boolean success
function M.stop_session()
	if not state.terminal.bufnr or not vim.api.nvim_buf_is_valid(state.terminal.bufnr) then
		vim.notify("[manim-nvim] No active session", vim.log.levels.WARN)
		return false
	end

	-- Stop the job if channel is active
	if state.terminal.chan_id then
		vim.fn.jobstop(state.terminal.chan_id)
	end

	-- Close the buffer
	vim.api.nvim_buf_delete(state.terminal.bufnr, { force = true })
	vim.notify("[manim-nvim] Session stopped", vim.log.levels.INFO)

	-- Reset state
	state.terminal.bufnr = nil
	state.terminal.chan_id = nil
	state.terminal.win_id = nil

	return true
end

---Restart the session with the same scene
---@return boolean success
function M.restart_session()
	if not state.scene_name or not state.file_path then
		vim.notify("[manim-nvim] No previous session to restart", vim.log.levels.WARN)
		return false
	end

	local scene = state.scene_name
	local file = state.file_path

	M.stop_session()

	-- Small delay to ensure cleanup
	vim.defer_fn(function()
		M.start_session(file, scene)
	end, 100)

	return true
end

---Focus the terminal window
---@return boolean success
function M.focus_terminal()
	if not state.terminal.win_id or not vim.api.nvim_win_is_valid(state.terminal.win_id) then
		vim.notify("[manim-nvim] No active terminal", vim.log.levels.WARN)
		return false
	end

	vim.api.nvim_set_current_win(state.terminal.win_id)
	return true
end

---Send text to terminal
---@param text string Text to send
---@return boolean success
function M.send_to_terminal(text)
	if not state.terminal.chan_id then
		vim.notify("[manim-nvim] No active session", vim.log.levels.WARN)
		return false
	end

	-- Check if this is multiline code
	local has_newline = text:find("\n") ~= nil

	if has_newline then
		-- For multiline code, use IPython's %cpaste mode
		-- This handles indentation and multi-line blocks properly
		vim.api.nvim_chan_send(state.terminal.chan_id, "%cpaste -q\n")
		-- Small delay to let IPython enter cpaste mode
		vim.defer_fn(function()
			vim.api.nvim_chan_send(state.terminal.chan_id, text .. "\n--\n")
		end, 50)
	else
		-- Single line - send directly
		vim.api.nvim_chan_send(state.terminal.chan_id, text .. "\n")
	end

	return true
end

---Run current line in terminal
---@return boolean success
function M.run_line()
	local line = vim.api.nvim_get_current_line()
	return M.send_to_terminal(line)
end

---Run visual selection in terminal
---@return boolean success
function M.run_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

	-- Handle partial line selection
	if #lines == 1 then
		local start_col = start_pos[3]
		local end_col = end_pos[3]
		lines[1] = string.sub(lines[1], start_col, end_col)
	end

	local text = table.concat(lines, "\n")
	return M.send_to_terminal(text)
end

return M
