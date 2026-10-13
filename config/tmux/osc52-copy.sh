#!/bin/sh
# shell-inits osc52-copy.sh - copy stdin to the workstation clipboard via OSC 52.
# Works over ssh, docker run -it and nested sessions: the escape sequence is
# plain terminal output, no X11/Wayland sockets required (the terminal itself
# must support OSC 52 - kitty, wezterm, iterm2, alacritty, windows terminal).
#
# Used by the tmux copy-mode `y` binding. Writing directly to the tmux client
# ttys makes it independent of tmux's own clipboard emission (which is buggy
# in some versions).
set -eu

data=$(base64 | tr -d '\n')
seq=$(printf '\033]52;c;%s\007' "$data")

if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
  # write to every attached tmux client's terminal
  for tty in $(tmux list-clients -F '#{client_tty}' 2>/dev/null); do
    if [ -w "$tty" ]; then
      printf '%s' "$seq" >"$tty" 2>/dev/null || true
    fi
  done
elif [ -w /dev/tty ]; then
  printf '%s' "$seq" >/dev/tty 2>/dev/null || true
fi
