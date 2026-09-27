#!/usr/bin/env bash
# Drives manim-nvim inside a detached tmux session, so an agent (or a human)
# can open a scene, write/select code in the Neovim buffer, send it to the
# running manimgl embed shell, and read back what happened -- the same round
# trip a human does by hand, scripted.
#
# manim-nvim is itself a TUI wrapping a second TUI (the :terminal split
# running manimgl's IPython embed shell). tmux drives the outer nvim; the
# plugin's own send_to_terminal()/checkpoint_paste() drive the inner one --
# this script never types into the terminal split directly.
#
# Usage:
#   ./driver.sh start [file] [scene]     Launch nvim+tmux, open file, :ManimStart scene
#                                         (file defaults to test_scene.py, scene to Interactive)
#   ./driver.sh keys <keys...>           tmux send-keys into the nvim pane, literally
#   ./driver.sh ex <command>             Run an Ex command (":ManimSend foo", ":ManimEmbed", ...)
#   ./driver.sh type <line> [<line> ...] Open a scratch buffer (:enew) and insert these lines
#   ./driver.sh run-line                 Put cursor on line 1 of current buffer, press run_line keymap
#   ./driver.sh run-selection            Visually select whole buffer, press run_selection keymap
#   ./driver.sh checkpoint [<line> ...]  type(lines) + visually select all + checkpoint_paste keymap
#   ./driver.sh wait <pattern> [timeout] Poll capture-pane for a regex (default timeout 10s)
#   ./driver.sh capture                  Print the current pane contents
#   ./driver.sh stop                     :ManimStop
#   ./driver.sh quit                     :qa! and kill the tmux session
#
# IMPORTANT when waiting for a result: tmux echoes sent text into the pane
# the instant it's typed, even while manimgl is still busy animating a
# previous self.play(). Waiting for your own code to appear in the capture
# proves it was sent, not that it finished. Wait for the *next* prompt
# instead, e.g. `./driver.sh wait 'In \[4\]:'` after a cell you expect to
# land as `In [3]`, or for a specific `Out[N]:`/error text.
#
# Direct (human) use needs none of this -- just run:
#   nvim -u test_init.lua test_scene.py
#
# Env overrides: SESSION (tmux session name), WIDTH/HEIGHT (pane size),
# NVIM_INIT (init file passed to -u), LEADER (must match test_init.lua's
# mapleader; default matches test_init.lua's " ").

set -euo pipefail

SESSION="${SESSION:-manim_nvim_driver}"
WIDTH="${WIDTH:-200}"
HEIGHT="${HEIGHT:-50}"
NVIM_INIT="${NVIM_INIT:-test_init.lua}"
LEADER="${LEADER:- }"

cd "$(dirname "${BASH_SOURCE[0]}")"

pane() { tmux capture-pane -t "$SESSION" -p; }

# Poll capture-pane for a regex instead of a fixed sleep: returns the instant
# the pattern shows up, and fails loudly (with the pane's last lines) if it
# never does.
wait_for() {
	local pattern="$1" timeout="${2:-10}"
	local max_ticks=$(( timeout * 5 )) tick=0  # 0.2s per tick
	while ! pane | grep -qE "$pattern"; do
		if (( tick >= max_ticks )); then
			echo "driver.sh: timed out waiting for /$pattern/ after ${timeout}s" >&2
			echo "--- last pane contents ---" >&2
			pane | tail -20 >&2
			return 1
		fi
		sleep 0.2
		tick=$(( tick + 1 ))
	done
}

require_session() {
	tmux has-session -t "$SESSION" 2>/dev/null || {
		echo "driver.sh: no session '$SESSION' -- run '$0 start' first" >&2
		exit 1
	}
}

cmd_start() {
	local file="${1:-test_scene.py}" scene="${2:-Interactive}"
	tmux kill-session -t "$SESSION" 2>/dev/null || true
	tmux new-session -d -s "$SESSION" -x "$WIDTH" -y "$HEIGHT" \
		"nvim -u '$NVIM_INIT' '$file'"
	wait_for "manim-nvim loaded!" 10
	# The setup() print()s pile up a hit-enter prompt on first draw; dismiss it.
	tmux send-keys -t "$SESSION" Enter
	wait_for "^${file##*/}" 5

	tmux send-keys -t "$SESSION" ":ManimStart $scene" Enter
	wait_for 'Session started|ERROR' 20
	if pane | grep -q ERROR; then
		echo "driver.sh: ManimStart reported an error:" >&2
		pane | tail -10 >&2
		return 1
	fi
	wait_for 'In \[[0-9]+\]:' 15
	echo "started: $SESSION ($file, scene=$scene)"
}

cmd_keys() { require_session; tmux send-keys -t "$SESSION" "$@"; }

cmd_ex() {
	require_session
	tmux send-keys -t "$SESSION" Escape ":$1" Enter
}

cmd_type() {
	require_session
	tmux send-keys -t "$SESSION" Escape ':enew' Enter
	wait_for '\[No Name\]|^\s*1\s*$' 5 || true
	tmux send-keys -t "$SESSION" 'i'
	local first=1
	for line in "$@"; do
		if [[ $first -eq 1 ]]; then
			first=0
		else
			tmux send-keys -t "$SESSION" Enter
		fi
		tmux send-keys -t "$SESSION" -l "$line"
	done
	tmux send-keys -t "$SESSION" Escape
}

cmd_run_line() {
	require_session
	tmux send-keys -t "$SESSION" 'gg' "${LEADER}mr"
}

cmd_run_selection() {
	require_session
	tmux send-keys -t "$SESSION" 'ggVG' "${LEADER}mr"
}

cmd_checkpoint() {
	require_session
	if [[ $# -gt 0 ]]; then
		cmd_type "$@"
	fi
	tmux send-keys -t "$SESSION" 'ggVG' "${LEADER}mp"
}

cmd_wait() { require_session; wait_for "$1" "${2:-10}"; pane; }
cmd_capture() { require_session; pane; }

cmd_stop() {
	require_session
	tmux send-keys -t "$SESSION" Escape ':ManimStop' Enter
	wait_for 'Session stopped|No active session' 10
}

cmd_quit() {
	require_session
	tmux send-keys -t "$SESSION" Escape ':qa!' Enter
	sleep 0.5
	tmux kill-session -t "$SESSION" 2>/dev/null || true
}

case "${1:-}" in
start) shift; cmd_start "$@" ;;
keys) shift; cmd_keys "$@" ;;
ex) shift; cmd_ex "$@" ;;
type) shift; cmd_type "$@" ;;
run-line) cmd_run_line ;;
run-selection) cmd_run_selection ;;
checkpoint) shift; cmd_checkpoint "$@" ;;
wait) shift; cmd_wait "$@" ;;
capture) cmd_capture ;;
stop) cmd_stop ;;
quit) cmd_quit ;;
*)
	sed -n '2,26p' "${BASH_SOURCE[0]}"
	exit 1
	;;
esac
