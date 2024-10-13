if vim.fn.has("nvim-0.7.0") ~= 1 then
	vim.api.nvim_err_writeln("manim-nvim requires at least nvim-0.7.0.")
	return
end

vim.api.nvim_create_user_command("ManimWatch", function()
	require("manim-nvim").start_watcher()
end, {})

vim.api.nvim_create_user_command("ManimStopWatch", function()
	require("manim-nvim").stop_watcher()
end, {})
