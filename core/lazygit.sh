#!/usr/bin/env bash
# core/lazygit.sh - lazygit release binary + pastel config (terminal git UI).
# Standalone: curl -fsSL <base>/core/lazygit.sh | bash -s -- --base-url <base>

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

LAZYGIT_REV=1

si_banner "core/lazygit"
si_distro_detect
si_pkgmap_load

# optional pinning: versions.env next to the scripts
_v=$(si_try_fetch_file versions.env) && source "$_v"

if si_state_has lazygit && si_have_cmd lazygit; then
  si_log "lazygit already initialized ($(si_state_file lazygit | xargs head -n1)), skipping"
  exit 0
fi

si_pkg_install unzip tar

_version=$(si_asset_github jesseduffield/lazygit "${LAZYGIT_VERSION:-latest}" \
  'lazygit_{ver}_linux_{arch}.tar.gz' 'checksums.txt')

_home=$(si_target_home)
si_deploy_file config/lazygit/config.yml "${_home}/.config/lazygit/config.yml"

si_state_mark lazygit "${LAZYGIT_REV}-${_version}"
si_log "lazygit ${_version} ready"
