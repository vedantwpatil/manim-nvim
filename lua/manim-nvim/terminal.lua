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

---Open terminal with manimgl interactive session.
---
---Reuses a previous session's window/buffer if either is still around --
---including one left behind after its job exited on its own, since on_exit
---only clears tracked state and never closes the leftover split -- instead
---of stacking a fresh split next to it.
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.start_session(file, scene)
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

	-- Snapshot whatever terminal is currently tracked -- a live session, or
	-- one whose job already exited but whose split/buffer was never closed.
	local old_bufnr = state.terminal.bufnr
	local old_chan_id = state.terminal.chan_id
	local old_win_id = state.terminal.win_id

	if old_chan_id then
		vim.fn.jobstop(old_chan_id)
	end

	local reused_window = old_win_id ~= nil and vim.api.nvim_win_is_valid(old_win_id)
	if reused_window then
		-- Reuse the existing split: jump to it and swap in a scratch buffer
		-- so the old terminal buffer has no window left showing it and can
		-- be wiped cleanly below.
		vim.api.nvim_set_current_win(old_win_id)
		vim.cmd("enew")
	elseif cfg.terminal_position == "bottom" then
		vim.cmd("botright new")
		vim.cmd("resize " .. math.floor(vim.o.lines * cfg.terminal_size))
	else
		vim.cmd("botright vnew")
		vim.cmd("vertical resize " .. math.floor(vim.o.columns * cfg.terminal_size))
	end

	if old_bufnr and vim.api.nvim_buf_is_valid(old_bufnr) then
		vim.api.nvim_buf_delete(old_bufnr, { force = true })
	end

	-- Store window ID before termopen (buffer will change)
	state.terminal.win_id = vim.api.nvim_get_current_win()

	-- Build command
	local cmd = string.format("%s %s %s", cfg.manim_cmd, vim.fn.shellescape(file), vim.fn.shellescape(scene))
	if cfg.default_flags ~= "" then
		cmd = cmd .. " " .. cfg.default_flags
	end

	-- Assigned right after termopen returns, below -- on_exit is inherently
	-- async (fires whenever the process actually dies), so by the time it
	-- runs this upvalue already holds this call's buffer number.
	local new_bufnr

	-- Start terminal with manimgl
	state.terminal.chan_id = vim.fn.termopen(cmd, {
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				-- Guard against a stale callback from a buffer that's since
				-- been replaced (e.g. by a restart) clobbering newer state.
				if state.terminal.bufnr ~= new_bufnr then
					return
				end
				remove_embed()
				if exit_code ~= 0 then
					vim.notify("[manim-nvim] Session exited with code: " .. exit_code, vim.log.levels.WARN)
				end
				-- Only the job is actually gone -- leave bufnr/win_id tracked
				-- so the next start_session() can find and reuse this split
				-- instead of stacking a new one next to it. Whatever finally
				-- deletes the buffer (that reuse, or stop_session()) clears
				-- them via the BufWipeout autocmd below.
				state.terminal.chan_id = nil
			end)
		end,
	})

	if state.terminal.chan_id == 0 then
		vim.notify("[manim-nvim] Failed to start terminal", vim.log.levels.ERROR)
		vim.cmd("close")
		return false
	end

	new_bufnr = vim.api.nvim_get_current_buf()
	state.terminal.bufnr = new_bufnr

	-- Reset state if buffer is wiped externally (e.g. :bwipeout) -- same
	-- stale-callback guard as on_exit above.
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = new_bufnr,
		once = true,
		callback = function()
			if state.terminal.bufnr ~= new_bufnr then
				return
			end
			remove_embed()
			state.terminal.chan_id = nil
			state.terminal.bufnr = nil
			state.terminal.win_id = nil
		end,
	})

	-- Set buffer options for terminal
	vim.bo[new_bufnr].buflisted = false
	vim.api.nvim_buf_set_name(new_bufnr, "manim://" .. scene)

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

	-- BufWipeout fires synchronously inside nvim_buf_delete, so by the time
	-- stop_session() returns, state.embed has already been cleared and the
	-- old marker line removed -- no delay needed before recording the new one.
	M.stop_session()

	if embed_bufnr and embed_lnum ~= nil and vim.api.nvim_buf_is_valid(embed_bufnr) then
		insert_embed_marker(embed_bufnr, embed_lnum)
	elseif embed_bufnr then
		vim.notify(
			"[manim-nvim] Could not restore self.embed() marker (buffer no longer valid)",
			vim.log.levels.WARN
		)
	end

	return M.start_session(file, scene)
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

---Get the current line's text
---@return string
local function get_line_text()
	return vim.api.nvim_get_current_line()
end

---Get the last visual selection's text
---@return string
local function get_selection_text()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)

	-- Handle partial line selection
	if #lines == 1 then
		local start_col = start_pos[3]
		local end_col = end_pos[3]
		lines[1] = string.sub(lines[1], start_col, end_col)
	end

	return table.concat(lines, "\n")
end

---Run current line in terminal
---@return boolean success
function M.run_line()
	return M.send_to_terminal(get_line_text())
end

---Run visual selection in terminal
---@return boolean success
function M.run_selection()
	return M.send_to_terminal(get_selection_text())
end

---Copy text to the system clipboard (the "+" and "*" registers), which is
---what manimlib's checkpoint_paste() reads from (via pyperclip.paste()).
---@param text string
local function copy_to_clipboard(text)
	vim.fn.setreg("+", text)
	vim.fn.setreg("*", text)
end

---Copy text to the clipboard and invoke manimlib's checkpoint_paste() inside
---the running self.embed() shell.
---
---checkpoint_paste() (only available in manimgl/3b1b's embed shell, not
---community manim) keys checkpoints off a leading "# comment" line in the
---pasted code: the first time a given comment is seen, it saves the scene's
---state under that key; on a later paste starting with the same comment, it
---restores that saved state before re-running the code. This lets you tweak
---a block and re-paste it without replaying every earlier block.
---@param text string
---@return boolean success
local function checkpoint_paste(text)
	if not state.terminal.chan_id then
		vim.notify("[manim-nvim] No active session", vim.log.levels.WARN)
		return false
	end

	if config.get().manim_cmd ~= "manimgl" then
		vim.notify(
			"[manim-nvim] checkpoint_paste() is a manimgl (3b1b) embed-shell feature; "
				.. "community manim does not implement it",
			vim.log.levels.WARN
		)
	end

	copy_to_clipboard(text)
	return M.send_to_terminal("checkpoint_paste()")
end

---Checkpoint-paste the current line: copy it to the clipboard, then run
---checkpoint_paste() in the embed shell.
---@return boolean success
function M.checkpoint_paste_line()
	return checkpoint_paste(get_line_text())
end

---Checkpoint-paste the last visual selection: copy it to the clipboard, then
---run checkpoint_paste() in the embed shell. Select the whole block including
---its leading "# comment" line so the checkpoint key matches on re-paste.
---@return boolean success
function M.checkpoint_paste_selection()
	return checkpoint_paste(get_selection_text())
end

---Reload the running scene in place: manimlib re-imports the scene file and
---re-runs construct() in the SAME process, keeping the GL window and IPython
---shell alive. Unlike restart_session(), which kills and re-spawns the whole
---manimgl process (slow: fresh Python/OpenGL/IPython startup), this reuses
---the existing process (fast) -- at the cost of always replaying construct()
---from the top, with no partial-resume like checkpoint_paste() gives.
---
---Bound to manimlib's `reload` embed-shell shortcut (scene_embed.py), which
---calls Scene.reload_scene() -> shell.run_line_magic("exit_raise", ""); this
---unwinds back to manimlib's run loop, which re-imports the module and reruns
---construct(). manimgl only -- community manim does not implement it.
---@return boolean success
function M.reload_scene()
	if not state.terminal.chan_id then
		vim.notify("[manim-nvim] No active session", vim.log.levels.WARN)
		return false
	end

	if config.get().manim_cmd ~= "manimgl" then
		vim.notify(
			"[manim-nvim] reload() is a manimgl (3b1b) embed-shell feature; "
				.. "community manim does not implement it",
			vim.log.levels.WARN
		)
	end

	return M.send_to_terminal("reload()")
end

---Capture the running scene's current camera orientation and copy it to the
---system clipboard as a `frame.reorient(...)` call, ready to paste into the
---scene file.
---
---Mirrors an undocumented Sublime shortcut Grant Sanderson uses (see the
---3b1b/Ben Sparks video linked in the README): pan the camera by hand in the
---live GL window until it looks right, then grab the exact orientation as
---code instead of guessing theta/phi/gamma by trial and error.
---
---Runs inside the embed shell rather than in Lua because the camera state
---only exists there. Uses `self.frame` (Scene.frame, set in Scene.setup()) --
---not a bare `frame`, which isn't one of the shortcuts scene_embed.py injects
----- and the `DEG` constant, which comes from the scene file's own
---`from manimlib import *` and lands in the embed shell's namespace via
---scene_embed.py's ModuleLoader use. manimgl only -- community manim's
---camera API differs.
---@return boolean success
function M.capture_frame()
	if not state.terminal.chan_id then
		vim.notify("[manim-nvim] No active session", vim.log.levels.WARN)
		return false
	end

	if config.get().manim_cmd ~= "manimgl" then
		vim.notify(
			"[manim-nvim] capture_frame relies on manimgl's self.frame/DEG embed-shell "
				.. "namespace; community manim does not expose them the same way",
			vim.log.levels.WARN
		)
	end

	local snippet = "import pyperclip as _mnvim_pc; "
		.. "_mnvim_e = self.frame.get_euler_angles() / DEG; "
		.. "_mnvim_c = self.frame.get_center(); "
		.. "_mnvim_s = 'frame.reorient({:.2f}, {:.2f}, {:.2f}, center=({:.2f}, {:.2f}, {:.2f}), height={:.2f})'.format("
		.. "_mnvim_e[0], _mnvim_e[1], _mnvim_e[2], _mnvim_c[0], _mnvim_c[1], _mnvim_c[2], self.frame.get_height()); "
		.. "_mnvim_pc.copy(_mnvim_s); print(_mnvim_s)"

	vim.notify("[manim-nvim] Camera orientation copied to clipboard", vim.log.levels.INFO)
	return M.send_to_terminal(snippet)
end

---Build the manimgl CLI invocation used to bake a final render.
---
---Unlike the interactive embed session, this is a one-shot, non-interactive
---process: `--prerun` does a first pass with animations skipped, just to
---compute the total frame count (accurate progress bar, and errors surface
---before time is spent animating); `--finder` reveals the output file in
---Finder when done and already implies -w/--write_file, but `-w` is passed
---too so the flag list still writes the file if `--finder` is ever dropped.
---@param file string
---@param scene string
---@param extra_flags string? Overrides config.default_flags when given
---@return string
local function build_render_cmd(file, scene, extra_flags)
	local cfg = config.get()
	local cmd = string.format(
		"%s %s %s --prerun --finder -w",
		cfg.manim_cmd, vim.fn.shellescape(file), vim.fn.shellescape(scene)
	)
	if extra_flags and extra_flags ~= "" then
		cmd = cmd .. " " .. extra_flags
	elseif cfg.default_flags ~= "" then
		cmd = cmd .. " " .. cfg.default_flags
	end
	return cmd
end

-- Exposed so tests can check the exact command line without spawning a
-- process (a real render needs ffmpeg/OpenGL and can run for minutes).
M._build_render_cmd = build_render_cmd

---Render the scene to a final video file.
---
---Runs build_render_cmd()'s one-shot manimgl invocation in its own split, so
---it doesn't disturb the interactive embed session tracked in `state` --
---this is the "bake to MP4 when happy with the scene" step, separate from
---the embed shell used to develop it. manimgl only -- --prerun/--finder
---aren't community-manim flags.
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (defaults to the active session's scene, else prompts)
---@param extra_flags string? Overrides config.default_flags when given
---@return boolean success
function M.render_scene(file, scene, extra_flags)
	file = file or vim.fn.expand("%:p")
	if file == "" then
		vim.notify("[manim-nvim] No file to render", vim.log.levels.ERROR)
		return false
	end

	scene = scene or state.scene_name or vim.fn.input("Scene name: ")
	if scene == "" then
		vim.notify("[manim-nvim] Scene name required", vim.log.levels.WARN)
		return false
	end

	if config.get().manim_cmd ~= "manimgl" then
		vim.notify(
			"[manim-nvim] --prerun/--finder are manimgl (3b1b) CLI flags; "
				.. "community manim uses a different render CLI",
			vim.log.levels.WARN
		)
	end

	local original_win = vim.api.nvim_get_current_win()
	vim.cmd("botright new")
	vim.cmd("resize " .. math.floor(vim.o.lines * 0.3))

	local bufnr = vim.api.nvim_get_current_buf()
	local cmd = build_render_cmd(file, scene, extra_flags)
	local chan_id = vim.fn.termopen(cmd, {
		on_exit = function(_, exit_code, _)
			vim.schedule(function()
				if exit_code == 0 then
					vim.notify("[manim-nvim] Render finished: " .. scene, vim.log.levels.INFO)
				else
					vim.notify("[manim-nvim] Render exited with code: " .. exit_code, vim.log.levels.WARN)
				end
			end)
		end,
	})

	if chan_id == 0 then
		vim.notify("[manim-nvim] Failed to start render", vim.log.levels.ERROR)
		vim.cmd("close")
		return false
	end

	vim.bo[bufnr].buflisted = false
	vim.api.nvim_buf_set_name(bufnr, "manim-render://" .. scene)
	vim.api.nvim_set_current_win(original_win)

	vim.notify("[manim-nvim] Rendering: " .. scene, vim.log.levels.INFO)
	return true
end

---Insert self.embed() before the cursor line, save, and start a manimgl session.
---If a terminal is already tracked -- a live session, or one left behind
---after its job exited on its own -- it is stopped first, synchronously
---(BufWipeout clears state.embed and strips the old marker inline during
---nvim_buf_delete), before the new marker is recorded. This ordering matters:
---inserting the new marker first would let that stale cleanup's remove_embed()
---strip it instead of the old one.
---On session exit (or terminal buffer wipeout) the inserted line is automatically removed.
---@param file string? File path (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.embed_and_start(file, scene)
	local embed_buf = vim.api.nvim_get_current_buf()
	local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed; insert BEFORE cursor line
	file = file or vim.api.nvim_buf_get_name(embed_buf)

	-- Check bufnr, not chan_id: a naturally-exited job leaves bufnr tracked
	-- (see start_session()'s on_exit) precisely so it still counts as "a
	-- terminal to clean up first" here.
	if state.terminal.bufnr then
		M.stop_session()
	end

	insert_embed_marker(embed_buf, lnum)
	return M.start_session(file, scene)
end

return M
