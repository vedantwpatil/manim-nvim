---@class TerminalState
---@field bufnr number|nil Buffer number of terminal
---@field chan_id number|nil Channel ID for sending commands
---@field win_id number|nil Window ID of terminal

---@class EmbedState
---@field bufnr number|nil Buffer where self.embed() was inserted
---@field lnum number|nil 0-indexed line number of the inserted self.embed()

---@class SessionState
---@field terminal TerminalState Terminal state
---@field scene_name string|nil Current scene name
---@field file_path string|nil Current file path
---@field embed EmbedState Embed tracking state

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
	embed = { bufnr = nil, lnum = nil },
}

---Remove the inserted self.embed() line and save the buffer
local function remove_embed()
	if state.embed.bufnr and state.embed.lnum ~= nil
		and vim.api.nvim_buf_is_valid(state.embed.bufnr) then
		vim.api.nvim_buf_set_lines(
			state.embed.bufnr, state.embed.lnum, state.embed.lnum + 1, false, {}
		)
		vim.api.nvim_buf_call(state.embed.bufnr, function()
			vim.cmd("silent! write")
		end)
	end
	state.embed.bufnr = nil
	state.embed.lnum = nil
end

---Insert "self.embed()" (matching the indentation of the line at lnum) into
---bufnr just before lnum, save the buffer, and record it as the current
---embed marker.
---@param bufnr number
---@param lnum number 0-indexed line to insert before
local function insert_embed_marker(bufnr, lnum)
	local cur_line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1] or ""
	local indent = cur_line:match("^(%s*)") or ""
	vim.api.nvim_buf_set_lines(bufnr, lnum, lnum, false, { indent .. "self.embed()" })
	vim.api.nvim_buf_call(bufnr, function()
		vim.cmd("silent! write")
	end)
	state.embed.bufnr = bufnr
	state.embed.lnum = lnum
end

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
				remove_embed()
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

	-- Reset state if buffer is wiped externally (e.g. :bwipeout)
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = state.terminal.bufnr,
		once = true,
		callback = function()
			remove_embed()
			state.terminal.chan_id = nil
			state.terminal.bufnr = nil
			state.terminal.win_id = nil
		end,
	})

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
	-- Capture the embed marker location (if any) before stop_session()'s
	-- BufWipeout handler clears state.embed and strips the line.
	local embed_bufnr, embed_lnum = state.embed.bufnr, state.embed.lnum

	M.stop_session()

	-- Small delay to ensure cleanup
	vim.defer_fn(function()
		if embed_bufnr and embed_lnum ~= nil and vim.api.nvim_buf_is_valid(embed_bufnr) then
			insert_embed_marker(embed_bufnr, embed_lnum)
		elseif embed_bufnr then
			vim.notify(
				"[manim-nvim] Could not restore self.embed() marker (buffer no longer valid)",
				vim.log.levels.WARN
			)
		end
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

---Insert self.embed() before the cursor line, save, and start a manimgl session.
---If a session is already active, it is stopped first and the new marker/session
---are deferred until after cleanup completes — mirroring restart_session()'s
---delay — since the old job's on_exit fires asynchronously and would otherwise
---clobber the new session's state or strip the newly-inserted marker.
---On session exit (or terminal buffer wipeout) the inserted line is automatically removed.
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.embed_and_start(file, scene)
	local embed_buf = vim.api.nvim_get_current_buf()
	local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed; insert BEFORE cursor line
	file = file or vim.api.nvim_buf_get_name(embed_buf)

	if state.terminal.chan_id then
		M.stop_session()
		-- Small delay to let the old job's async on_exit finish (it resets
		-- state.terminal fields and calls remove_embed() on whatever marker
		-- is current) before we record the new marker and start a new session.
		vim.defer_fn(function()
			insert_embed_marker(embed_buf, lnum)
			M.start_session(file, scene)
		end, 100)
		return true
	end

	insert_embed_marker(embed_buf, lnum)
	return M.start_session(file, scene)
end

return M
