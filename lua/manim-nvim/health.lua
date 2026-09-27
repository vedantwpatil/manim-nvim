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

	-- system clipboard (required for checkpoint_paste, which reads it via
	-- pyperclip on the manimgl side)
	if vim.fn.has("clipboard") == 1 and (vim.g.clipboard or vim.fn.executable("pbcopy") == 1
			or vim.fn.executable("xclip") == 1 or vim.fn.executable("xsel") == 1
			or vim.fn.executable("wl-copy") == 1) then
		h.ok("system clipboard provider found (checkpoint_paste enabled)")
	else
		h.warn(
			"no system clipboard provider found",
			{
				"Install pbcopy (macOS, built-in) / xclip / xsel / wl-clipboard (Linux)",
				"ManimCheckpointPaste will send stale clipboard content without one",
			}
		)
	end
end

return M
