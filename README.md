# manim-nvim

Interactive Manim development for Neovim, inspired by the [3Blue1Brown workflow](https://www.youtube.com/watch?v=rbu7Zu5X1zI).

## Features

- Interactive terminal session with manimgl
- Send code from editor to running session with a keybind
- Live OpenGL preview window
- File watcher for automatic recompilation

## Requirements

- Neovim >= 0.7.0
- [manimgl](https://github.com/3b1b/manim) (3b1b version) or [manim](https://www.manim.community/) (community version)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (optional, for file watcher)
- [entr](https://eradman.com/entrproject/) (optional, for file watcher)

# Note

Still in progress.
Current Issues

- Spawns multiple side buffers and doesn't use already existing ones
- Doesn't feature scene caching
- Doesn't feature checkpoint pasting

## Installation

### lazy.nvim

```lua
{
    'vedantpatil/manim-nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },  -- optional
    config = function()
        require('manim-nvim').setup()
    end,
    ft = 'python',  -- lazy load for Python files
}
```

### packer.nvim

```lua
use {
    'vedantpatil/manim-nvim',
    requires = { 'nvim-lua/plenary.nvim' },  -- optional
    config = function()
        require('manim-nvim').setup()
    end,
}
```

## Configuration

```lua
require('manim-nvim').setup({
    -- Terminal split position: 'right' or 'bottom'
    terminal_position = 'right',

    -- Terminal size as fraction of screen (0.0-1.0)
    terminal_size = 0.4,

    -- Command to run manim
    manim_cmd = 'manimgl',  -- or 'manim' for community version

    -- Additional flags to pass to manim
    default_flags = '',

    -- Keymaps (set to false to disable all, or set individual keys to false)
    keymaps = {
        start_session = '<leader>mo',
        stop_session = '<leader>mc',
        run_line = '<leader>mr',
        run_selection = '<leader>mr',  -- visual mode
        focus_terminal = '<leader>mf',
        start_watcher = '<leader>mw',
        stop_watcher = '<leader>ms',
        embed = '<leader>me',          -- insert self.embed() and start session
    },
})
```

## Usage

### Interactive Session (Recommended)

1. Open a Python file with a Manim scene
2. Run `:ManimStart` and enter the scene name (e.g., `HelloWorld`)
3. A terminal opens on the right with manimgl running
4. Use `<leader>mr` to send the current line to the terminal
5. Select code in visual mode and press `<leader>mr` to run it
6. Run `:ManimStop` to end the session

### Embed Workflow

1. Place the cursor on the line where you want to drop into an interactive `self.embed()` shell
2. Run `:ManimEmbed [scene]` (or press `<leader>me`)
3. manim-nvim inserts `self.embed()` above the cursor line, saves the file, and starts the manimgl session
4. When you stop the session (`:ManimStop`), close the terminal buffer, or the process exits, the inserted line is automatically removed
5. `:ManimRestart` reinserts the marker before restarting, so the restarted session behaves like the one it replaced

### Commands

| Command               | Description                                     |
| --------------------- | ------------------------------------------------ |
| `:ManimStart [scene]` | Start interactive manimgl session                |
| `:ManimStop`          | Stop the current session                         |
| `:ManimRestart`       | Restart session with same scene                  |
| `:ManimFocus`         | Focus the terminal window                        |
| `:ManimRunLine`       | Run current line                                 |
| `:ManimRunSelection`  | Run visual selection                             |
| `:ManimSend {text}`   | Send arbitrary text to session                   |
| `:ManimEmbed [scene]` | Insert self.embed() at cursor and start session  |
| `:ManimWatch [scene]` | Start file watcher                               |
| `:ManimStopWatch`     | Stop file watcher                                |

### Default Keymaps

| Mode | Key          | Action                                |
| ---- | ------------ | -------------------------------------- |
| n    | `<leader>mo` | Start Manim session                   |
| n    | `<leader>mc` | Stop Manim session                    |
| n    | `<leader>mr` | Run current line                      |
| v    | `<leader>mr` | Run visual selection                  |
| n    | `<leader>mf` | Focus terminal                        |
| n    | `<leader>me` | Insert self.embed() and start session |
| n    | `<leader>mw` | Start file watcher                    |
| n    | `<leader>ms` | Stop file watcher                     |

## Health Check

Run `:checkhealth manim-nvim` to verify your setup.
