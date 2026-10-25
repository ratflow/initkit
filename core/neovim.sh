#!/usr/bin/env bash
# core/neovim.sh - neovim + LazyVim with a personal, language-agnostic layer:
# catppuccin theme, snacks explorer tweaks, OSC52 clipboard over ssh.
# Language-specific plugins (C++/rust/go/debuggers) are intentionally out of scope.
# Standalone: curl -fsSL <base>/core/neovim.sh | bash -s -- --base-url <base>
# Env: SHELL_INITS_NVIM_BOOTSTRAP=1  -> also sync plugins headlessly (docker builds)

set -euo pipefail

# --- shell-inits preamble v2 (identical across core/ and sets/ scripts) -----
DEFAULT_BASE_URL="https://raw.githubusercontent.com/ratflow/initkit/master"  # override with --base-url or SHELL_INITS_BASE_URL
# SI_BASE_URL precedence: --base-url arg > SHELL_INITS_BASE_URL env > value
# inherited from a parent shell-inits process (sets -> core) > local checkout
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
  echo "shell-inits: base URL required (--base-url URL, SHELL_INITS_BASE_URL env, or run from a checkout)" >&2
  exit 1
fi
if [[ $SI_MODE == local ]]; then
  for _si_lib in common distro fetch pkg state asset run-set; do
    source "$SI_ROOT/lib/${_si_lib}.sh"
  done
  unset _si_lib
else
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || { echo "shell-inits: curl or wget required" >&2; exit 1; }
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

NEOVIM_REV=5
NVIM_MIN_MAJOR=0
NVIM_MIN_MINOR=10

si_banner "core/neovim"
si_distro_detect
si_pkgmap_load

if si_state_has neovim "$NEOVIM_REV" && si_have_cmd nvim; then
  si_log "neovim already initialized (rev ${NEOVIM_REV}), skipping"
  exit 0
fi

# lazyvim opens lazygit; make sure it is there first
si_ensure_core lazygit

# gcc + libc headers: nvim-treesitter compiles parsers locally (libc6-dev is
# only a Recommends of gcc, so it must be explicit with --no-install-recommends)
si_pkg_install neovim ripgrep fd-find gcc libc6-dev ca-certificates

# LazyVim requires nvim >= 0.10
read -r _maj _min <<<"$(nvim --version | head -n1 | sed -n 's/.*v\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2/p')"
[[ ${_maj:-0} -gt $NVIM_MIN_MAJOR || (${_maj:-0} -eq $NVIM_MIN_MAJOR && ${_min:-0} -ge $NVIM_MIN_MINOR) ]] \
  || si_die "neovim ${_maj:-?}.${_min:-?} is too old for LazyVim (needs >= ${NVIM_MIN_MAJOR}.${NVIM_MIN_MINOR})"

_home=$(si_target_home)

# ubuntu ships the binary as fdfind; LazyVim/telescope expect `fd`
if ! si_have_cmd fd && si_have_cmd fdfind; then
  si_as_user 'mkdir -p ~/.local/bin && ln -sf "$(command -v fdfind)" ~/.local/bin/fd'
fi

# treesitter parsers are compiled locally; without a C compiler they fail
if ! si_have_cmd cc && ! si_have_cmd gcc; then
  si_warn "no C compiler found; nvim-treesitter parsers may fail to build (apt install gcc)"
fi

# replace any pre-existing nvim config (backed up), keep plugin data as-is
if [[ -e ${_home}/.config/nvim ]]; then
  si_backup_existing "${_home}/.config/nvim"
  rm -rf "${_home}/.config/nvim"
fi

_nvim_config=${_home}/.config/nvim
for _f in \
  init.lua \
  bootstrap.lua \
  lua/config/clipboard.lua \
  lua/config/lazy.lua \
  lua/config/options.lua \
  lua/config/keymaps.lua \
  lua/config/autocmds.lua \
  lua/config/treesitter_parsers.lua \
  lua/plugins/colorscheme.lua \
  lua/plugins/snacks.lua \
  lua/plugins/indent-blankline.lua \
  lua/plugins/terminal.lua \
  lua/plugins/treesitter.lua
do
  si_deploy_file "config/nvim/${_f}" "${_nvim_config}/${_f}"
done
unset _f

# pre-fetch spell files so the first open of a text/markdown file does not
# prompt "Download it?" (best effort - skipped silently when offline)
si_as_user 'mkdir -p ~/.local/share/nvim/site/spell && cd ~/.local/share/nvim/site/spell \
  && for _f in en.utf-8.spl en.utf-8.sug pl.utf-8.spl; do \
    [ -f "$_f" ] || curl -fsSLO "https://ftp.nluug.nl/pub/vim/runtime/spell/${_f}" 2>/dev/null || true; \
  done'

# tree-sitter CLI as a release binary: stops LazyVim from trying to install it
# through mason (which needs node) on every start; nvim-treesitter main branch
# ships prebuilt parsers, the CLI is only needed for edge cases
case $(uname -m) in
  x86_64)        _ts_asset='tree-sitter-linux-x64.gz' ;;
  aarch64|arm64) _ts_asset='tree-sitter-linux-arm64.gz' ;;
  *)             _ts_asset='' ;;
esac
if [[ -n $_ts_asset ]] && ! si_have_cmd tree-sitter; then
  si_asset_github tree-sitter/tree-sitter "${TREE_SITTER_VERSION:-latest}" "$_ts_asset" || \
    si_warn "tree-sitter CLI install failed; LazyVim may attempt a mason install"
fi
unset _ts_asset

# optional headless plugin sync (docker builds / explicit request).
# Two separate nvim invocations on purpose: treesitter parser installs are
# unreliable when run in the same session as the very first Lazy sync.
if [[ ${SHELL_INITS_NVIM_BOOTSTRAP:-0} == 1 ]]; then
  si_log "bootstrapping lazyvim + treesitter parsers headlessly (this can take a while)"
  si_as_user 'nvim --headless "+Lazy! sync" +qa' \
    || si_warn "headless plugin sync reported errors; first interactive start will retry"
  si_as_user 'nvim --headless "+lua dofile(vim.fn.stdpath(\"config\")..\"/bootstrap.lua\")" +qa' \
    || si_warn "headless bootstrap reported errors; first interactive start will retry"
fi

si_state_mark neovim "$NEOVIM_REV"
si_log "neovim $(nvim --version | head -n1) ready with LazyVim at ${_nvim_config}"
