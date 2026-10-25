#!/bin/sh
# initkit container entrypoint: attach to or create the default tmux
# session 'main'. Set SHELL_INITS_NO_TMUX=1 for a plain login zsh.
set -e
if [ "${SHELL_INITS_NO_TMUX:-0}" = "1" ]; then
  exec "${SHELL:-/usr/bin/zsh}" -l
fi
exec tmux new -As main
