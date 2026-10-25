#!/usr/bin/env bash
# sets/zsh-tmux-neovim.sh - zsh + fzf + tmux + lazyvim + lazygit
# Single-command entry point, curl-able:
#   curl -fsSL <base>/sets/zsh-tmux-neovim.sh | bash -s -- --base-url <base>
# Env: SHELL_INITS_SKIP=tmux,neovim   exclude components
#      SHELL_INITS_FORCE=1            reinstall everything
#      SHELL_INITS_NVIM_BOOTSTRAP=1   sync nvim plugins headlessly right away

set -euo pipefail

# --- initkit preamble v2 (identical across core/ and sets/ scripts) -----
DEFAULT_BASE_URL="https://raw.githubusercontent.com/ratflow/initkit/master"  # override with --base-url or SHELL_INITS_BASE_URL
# SI_BASE_URL precedence: --base-url arg > SHELL_INITS_BASE_URL env > value
# inherited from a parent initkit process (sets -> core) > local checkout
SI_BASE_URL=${SHELL_INITS_BASE_URL:-${SI_BASE_URL:-}}
_si_self=${BASH_SOURCE[0]:-}
while [[ $# -gt 0 ]]; do
  case $1 in
    --base-url) SI_BASE_URL=${2:?--base-url needs a value}; shift 2 ;;
    *) shift ;;
  esac
done
# local mode only when this script really lives inside a checkout (a copy
# fetched to a temp file by run-set.sh must not be mistaken for a checkout)
if [[ -z $SI_BASE_URL && -n $_si_self && -f $_si_self ]] \
  && SI_ROOT=$(cd -- "$(dirname -- "$_si_self")/.." && pwd) \
  && [[ -f $SI_ROOT/lib/common.sh ]]; then
  SI_MODE=local
else
  SI_MODE=remote
  [[ -n $SI_BASE_URL ]] || SI_BASE_URL=$DEFAULT_BASE_URL
fi
export SI_BASE_URL SI_MODE SI_ROOT
if [[ -z $SI_BASE_URL && $SI_MODE != local ]]; then
  echo "initkit: base URL required (--base-url URL, SHELL_INITS_BASE_URL env, or run from a checkout)" >&2
  exit 1
fi
if [[ $SI_MODE == local ]]; then
  for _si_lib in common distro fetch pkg state asset run-set; do
    source "$SI_ROOT/lib/${_si_lib}.sh"
  done
  unset _si_lib
else
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || { echo "initkit: curl or wget required" >&2; exit 1; }
  _si_tmp=$(mktemp -d)
  for _si_lib in common distro fetch pkg state asset run-set; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL "${SI_BASE_URL%/}/lib/${_si_lib}.sh" -o "${_si_tmp}/${_si_lib}.sh"
    else
      wget -qO "${_si_tmp}/${_si_lib}.sh" "${SI_BASE_URL%/}/lib/${_si_lib}.sh"
    fi
    source "${_si_tmp}/${_si_lib}.sh"
  done
  unset _si_lib _si_tmp
fi
# --- end preamble ------------------------------------------------------------

SET_NAME="zsh-tmux-neovim"
COMPONENTS=(fzf zsh tmux lazygit neovim)

si_banner "set: ${SET_NAME}"
si_distro_detect
si_pkgmap_load

si_run_set

si_set_default_shell_zsh
si_print_summary
