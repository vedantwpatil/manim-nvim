local M = {}

function M.check()
	local h = vim.health
	h.start("manim-nvim")

	-- Neovim version
	if vim.fn.has("nvim-0.7.0") == 1 then
		h.ok("Neovim >= 0.7.0")
	else
		h.error("Neovim >= 0.7.0 required")
	end

	-- manim binary
	local ok, config = pcall(require, "manim-nvim.config")
	local manim_cmd = ok and config.get().manim_cmd or "manimgl"
	if vim.fn.executable(manim_cmd) == 1 then
		h.ok(manim_cmd .. " found")
	else
		h.error(manim_cmd .. " not found", { "Install manimgl: pip install manimgl", "Or manim: pip install manim" })
	end

	-- plenary.nvim
	if pcall(require, "plenary") then
		h.ok("plenary.nvim found (watcher enabled)")
	else
		h.warn(
			"plenary.nvim not found",
			{ "Install via your plugin manager", "File watcher feature will be unavailable" }
		)
	end

	-- entr
	if vim.fn.executable("entr") == 1 then
		h.ok("entr found (watcher enabled)")
	else
		h.warn(
			"entr not found",
			{ "Install: brew install entr  /  apt install entr", "File watcher feature will be unavailable" }
		)
	end
end

return M
