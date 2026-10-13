#!/usr/bin/env bash
# core/zsh.sh - zsh with a fast pastel prompt (async git info, big-repo safe),
# fzf integration and two vendored plugins (autosuggestions, syntax highlighting)
# cloned as plain git repos. No plugin manager.
# Standalone: curl -fsSL <base>/core/zsh.sh | bash -s -- --base-url <base>

set -euo pipefail

# --- shell-inits preamble v1 (identical across core/ and sets/ scripts) -----
DEFAULT_BASE_URL=""  # per-deployment fallback, e.g. https://git.example.com/shell-inits/raw/main
SI_BASE_URL=${SHELL_INITS_BASE_URL:-}
_si_self=${BASH_SOURCE[0]:-}
while [[ $# -gt 0 ]]; do
  case $1 in
    --base-url) SI_BASE_URL=${2:?--base-url needs a value}; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -z $SI_BASE_URL && -n $_si_self && -f $_si_self ]]; then
  SI_MODE=local
  SI_ROOT=$(cd -- "$(dirname -- "$_si_self")/.." && pwd)
elif [[ -z $SI_BASE_URL && -n $DEFAULT_BASE_URL ]]; then
  SI_MODE=remote
  SI_BASE_URL=$DEFAULT_BASE_URL
else
  SI_MODE=remote
fi
export SI_BASE_URL SI_MODE SI_ROOT
if [[ -z $SI_BASE_URL && $SI_MODE != local ]]; then
  echo "shell-inits: base URL required (--base-url URL, SHELL_INITS_BASE_URL env, or run from a checkout)" >&2
  exit 1
fi
if [[ $SI_MODE == local ]]; then
  source "$SI_ROOT/lib/common.sh"
else
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || { echo "shell-inits: curl or wget required" >&2; exit 1; }
  _si_tmp=$(mktemp -d)
  for _si_lib in common distro fetch pkg state asset; do
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

ZSH_REV=2
ZSH_PLUGINS=(
  zsh-users/zsh-autosuggestions
  zsh-users/zsh-syntax-highlighting
)

si_banner "core/zsh"
si_distro_detect
si_pkgmap_load

if si_state_has zsh "$ZSH_REV" && si_have_cmd zsh; then
  si_log "zsh already initialized (rev ${ZSH_REV}), skipping"
  exit 0
fi

# fzf provides key bindings and completion integrated by the .zshrc below
si_ensure_core fzf

si_pkg_install zsh git ca-certificates

_home=$(si_target_home)

# git: make `git status` cheap even in very large repositories
si_as_user 'git config --global core.untrackedCache true'
si_as_user 'git config --global core.fsmonitor true'

# vendored plugins (plain clones, no manager)
for _repo in "${ZSH_PLUGINS[@]}"; do
  _name=${_repo##*/}
  si_as_user "mkdir -p ~/.zsh/plugins && \
    if [ -d ~/.zsh/plugins/${_name}/.git ]; then \
      git -C ~/.zsh/plugins/${_name} pull -q --ff-only || true; \
    else \
      git clone -q --depth 1 https://github.com/${_repo} ~/.zsh/plugins/${_name}; \
    fi" || si_warn "failed to clone ${_repo}"
done
unset _repo _name

si_backup_existing "${_home}/.zshrc"
si_backup_existing "${_home}/.zshenv"
si_deploy_file config/zsh/zshenv "${_home}/.zshenv"
si_deploy_file config/zsh/zshrc "${_home}/.zshrc"
si_deploy_file config/zsh/prompt.zsh "${_home}/.zsh/prompt.zsh"

si_state_mark zsh "$ZSH_REV"
si_log "zsh $(zsh --version | cut -d' ' -f2) ready, config in ${_home}"
