---File watcher module for manim-nvim
---Uses entr to watch files and recompile on save

local M = {}

local Job = require("plenary.job")

---@type Job|nil
local watcher_job = nil

---@type string|nil
local current_scene = nil

---Check if watcher is active
---@return boolean
function M.is_active()
	return watcher_job ~= nil
end

---Get current watched scene
---@return string|nil
function M.get_scene()
	return current_scene
end

---Start file watcher
---@param file string? File to watch (defaults to current buffer)
---@param scene string? Scene name (prompts if not provided)
---@return boolean success
function M.start(file, scene)
	if watcher_job then
		vim.notify("[manim-nvim] Watcher already running. Stop it first.", vim.log.levels.WARN)
		return false
	end

	file = file or vim.fn.expand("%")
	if file == "" then
		vim.notify("[manim-nvim] No file to watch", vim.log.levels.ERROR)
		return false
	end

	scene = scene or vim.fn.input("Enter scene name: ")
	if scene == "" then
		vim.notify("[manim-nvim] Scene name required", vim.log.levels.WARN)
		return false
	end

	local cmd = string.format("echo %s | entr -c manim %s %s -pqk", file, file, scene)

	watcher_job = Job:new({
		command = "bash",
		args = { "-c", cmd },
		on_exit = function(_, return_val)
			vim.schedule(function()
				if return_val ~= 0 then
					vim.notify("[manim-nvim] Watcher exited with code: " .. return_val, vim.log.levels.WARN)
				end
			end)
			watcher_job = nil
			current_scene = nil
		end,
	})

	watcher_job:start()
	current_scene = scene
	vim.notify("[manim-nvim] Watcher started for scene: " .. scene, vim.log.levels.INFO)
	return true
end

---Stop file watcher
---@return boolean success
function M.stop()
	if not watcher_job then
		vim.notify("[manim-nvim] No active watcher", vim.log.levels.WARN)
		return false
	end

	watcher_job:shutdown()
	watcher_job = nil
	current_scene = nil
	vim.notify("[manim-nvim] Watcher stopped", vim.log.levels.INFO)
	return true
end

return M
