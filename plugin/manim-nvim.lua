---@brief [[
---Plugin entry point for manim-nvim
---This file is auto-loaded by Neovim and registers user commands
---@brief ]]

-- Prevent loading twice
if vim.g.loaded_manim_nvim then
	return
end

-- Check Neovim version
if vim.fn.has("nvim-0.7.0") ~= 1 then
	vim.api.nvim_err_writeln("[manim-nvim] requires Neovim >= 0.7.0")
	return
end

vim.g.loaded_manim_nvim = true

-- Create user commands
local function create_commands()
	local cmd = vim.api.nvim_create_user_command

	-- Session commands
	cmd("ManimStart", function(opts)
		local scene = opts.args ~= "" and opts.args or nil
		require("manim-nvim").start_session(nil, scene)
	end, {
		nargs = "?",
		desc = "Start interactive manimgl session",
		complete = function()
			-- Could add scene completion here in the future
			return {}
		end,
	})

	cmd("ManimStop", function()
		require("manim-nvim").stop_session()
	end, { desc = "Stop Manim session" })

	cmd("ManimRestart", function()
		require("manim-nvim").restart_session()
	end, { desc = "Restart Manim session with same scene" })

	cmd("ManimFocus", function()
		require("manim-nvim").focus_terminal()
	end, { desc = "Focus Manim terminal window" })

	-- Code execution commands
	cmd("ManimRunLine", function()
		require("manim-nvim").run_line()
	end, { desc = "Run current line in Manim session" })

	cmd("ManimRunSelection", function()
		require("manim-nvim").run_selection()
	end, { range = true, desc = "Run visual selection in Manim session" })

	cmd("ManimSend", function(opts)
		require("manim-nvim").send_to_terminal(opts.args)
	end, { nargs = "+", desc = "Send text to Manim session" })

	-- Watcher commands
	cmd("ManimWatch", function(opts)
		local scene = opts.args ~= "" and opts.args or nil
		require("manim-nvim").start_watcher(nil, scene)
	end, { nargs = "?", desc = "Start Manim file watcher" })

	cmd("ManimStopWatch", function()
		require("manim-nvim").stop_watcher()
	end, { desc = "Stop Manim file watcher" })
end

create_commands()
