# manim-nvim

Interactive Manim development for Neovim, inspired by the [3Blue1Brown workflow](https://www.youtube.com/watch?v=rbu7Zu5X1zI).

## Features

- Interactive terminal session with manimgl
- Send code from editor to running session with a keybind
- Checkpoint-paste a line/selection into the embed shell, reverting to a
  saved scene state when re-pasting a block with the same leading `# comment`
- Reload the running scene in place (no process restart)
- Capture the live camera orientation as a `frame.reorient(...)` call
- Render the scene to a final video file
- Live OpenGL preview window
- File watcher for automatic recompilation

## Requirements

- Neovim >= 0.7.0
- [manimgl](https://github.com/3b1b/manim) (3b1b version) or [manim](https://www.manim.community/) (community version)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (optional, for file watcher)
- [entr](https://eradman.com/entrproject/) (optional, for file watcher)

# Note

Still in progress.

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
        checkpoint_paste = '<leader>mp',           -- checkpoint-paste current line
        checkpoint_paste_selection = '<leader>mp', -- checkpoint-paste visual selection
        reload = '<leader>ml',                     -- reload running scene in place
        capture_frame = '<leader>mv',              -- copy camera orientation as frame.reorient(...)
        render = '<leader>mR',                     -- render scene to a final video file
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

### Checkpoint Paste (manimgl only)

Inside a running `self.embed()` shell, manimlib exposes `checkpoint_paste()`:
it reads the system clipboard, and if the pasted code starts with a `#
comment` line it has seen before, it first reverts the scene to the state it
had the first time that comment was pasted, then re-runs the code. This lets
you tweak one block of a scene and re-run just that block, instead of
replaying every earlier block by hand.

1. Write scene code in blocks, each starting with a `# comment` naming it:
   ```python
   # Intro
   self.play(Write(title))
   self.wait()
   ```
2. With the cursor on the line (or a visual selection covering the whole
   block, comment included), press `<leader>mp`
3. This copies the text to the clipboard and runs `checkpoint_paste()` in the
   embed shell
4. Edit the block and press `<leader>mp` again: the scene reverts to right
   before "Intro" first ran, then replays your edited version

This requires an active `self.embed()` session (see Embed Workflow above) and
is a `manimgl` feature — community `manim` does not implement
`checkpoint_paste()`.

### Reload (manimgl only)

`:ManimRestart` kills and re-spawns the whole manimgl process — every restart
pays full Python/manimlib import and OpenGL window startup cost.
`:ManimReload` (`<leader>ml`) instead sends `reload()` to the running embed
shell: manimlib re-imports the scene file and re-runs `construct()` in the
*same* process, keeping the GL window and IPython state alive. Use it after
editing the file to pick up the changes quickly; unlike `checkpoint_paste()`
it always replays `construct()` from the top, it just avoids the process
relaunch. Requires an active `self.embed()` session; community `manim` does
not implement `reload()`.

### Capture Camera Frame (manimgl only)

3D scenes let you pan the camera interactively with the mouse while an embed
session is running, but finding a good angle that way is easy to lose --
there's no way to read back what orientation you ended up at. This mirrors an
undocumented shortcut from the workflow this plugin is based on: pan by hand
until it looks right, then grab the exact `frame.reorient(...)` call instead
of guessing `theta`/`phi`/`gamma` degrees by trial and error.

1. With an active `self.embed()` session showing a 3D scene, pan/rotate the
   camera to the angle you want
2. Press `<leader>mv` (`:ManimCaptureFrame`)
3. The current orientation is printed in the embed shell and copied to the
   clipboard as e.g. `frame.reorient(-30.00, 70.00, 0.00, center=(0.00, 0.00, 0.00), height=8.00)`
4. Paste it into `construct()` (or `self.frame.animate.reorient(...)` inside
   a `self.play(...)` to animate the pan) so the angle is reproducible on the
   next run

Requires an active `self.embed()` session; relies on `self` (always in
scope, since `self.embed()` is called from inside a method) and the `DEG`
constant, which is in the embed shell's namespace via the scene file's
`from manimlib import *`.

### Render (manimgl only)

`:ManimRender [scene]` bakes the scene to a final video file: a one-shot,
non-interactive `manimgl` invocation, separate from the interactive embed
session used to develop the scene. It always passes `--prerun` (a first pass
with animations skipped, just to compute the total frame count so the
progress bar is accurate and errors surface before time is spent animating)
and `--finder -w` (reveal the output file when done, and write it).

```
:ManimRender HelloWorld
```

or press `<leader>mR` with no scene name to render the active session's scene.

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
| `:ManimCheckpointPaste` | Checkpoint-paste current line into embed shell |
| `:ManimCheckpointPasteSelection` | Checkpoint-paste visual selection into embed shell |
| `:ManimReload`         | Reload running scene in place (manimgl only)     |
| `:ManimCaptureFrame`   | Copy camera orientation as frame.reorient(...) (manimgl only) |
| `:ManimRender [scene]` | Render scene to a final video file (manimgl only) |
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
| n    | `<leader>mp` | Checkpoint-paste current line         |
| v    | `<leader>mp` | Checkpoint-paste visual selection     |
| n    | `<leader>ml` | Reload running scene in place         |
| n    | `<leader>mv` | Copy camera orientation to clipboard  |
| n    | `<leader>mR` | Render scene to video file            |
| n    | `<leader>mw` | Start file watcher                    |
| n    | `<leader>ms` | Stop file watcher                     |

## Health Check

Run `:checkhealth manim-nvim` to verify your setup.

## Testing / Driving the Plugin

`test_init.lua` + `test_scene.py` are a minimal manual setup:

```bash
nvim -u test_init.lua test_scene.py
```

`driver.sh` scripts that same setup inside `tmux` (`send-keys` /
`capture-pane`), so it can be run and inspected non-interactively — useful
for verifying a change end-to-end without sitting at the keyboard:

```bash
./driver.sh start                 # nvim + :ManimStart Interactive
./driver.sh type 'circle = Circle()' 'self.play(ShowCreation(circle))'
./driver.sh run-line               # send line 1
./driver.sh keys j '<leader>mr'    # send line 2 (or run-selection for the whole buffer)
./driver.sh checkpoint '# demo' 'square = Square()' 'self.add(square)'
./driver.sh capture                # read back the embed shell's output
./driver.sh stop && ./driver.sh quit
```

See the header of `driver.sh` for the full command list and a caveat about
telling a command's *echo* apart from its *completion*.
