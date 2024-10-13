local M = {}

local Job = require("plenary.job")
local watcher_job = nil

function M.start_watcher()
	local file = vim.fn.expand("%")
	local scene = vim.fn.input("Enter scene name: ")
	local cmd = string.format("echo %s | entr -c manim %s %s -pqk", file, file, scene)

	watcher_job = Job:new({
		command = "bash",
		args = { "-c", cmd },
		on_exit = function(j, return_val)
			print("Manim watcher exited with value: " .. return_val)
		end,
	})

	watcher_job:start()
	print("Manim watcher started for scene: " .. scene)
end

function M.stop_watcher()
	if watcher_job then
		watcher_job:shutdown()
		watcher_job = nil
		print("Manim watcher stopped")
	else
		print("No active Manim watcher")
	end
end

function M.setup(opts)
	opts = opts or {}

	-- Set up any configuration options here

	-- Set up keymaps
	vim.keymap.set("n", opts.watch_keymap or "<leader>mw", M.start_watcher, { desc = "Start Manim watcher" })
	vim.keymap.set("n", opts.stop_keymap or "<leader>ms", M.stop_watcher, { desc = "Stop Manim watcher" })
end

return M
