# lib/common.sh - shared helpers for all initkit scripts
# Sourced after the standard entry preamble (which exports SI_BASE_URL/SI_MODE/SI_ROOT).
set -euo pipefail

# --- logging (logs go to stderr; stdout is reserved for return values) -------

si_log()  { printf '[initkit] %s\n' "$*" >&2; }
si_warn() { printf '[initkit][warn] %s\n' "$*" >&2; }
si_die()  { printf '[initkit][error] %s\n' "$*" >&2; exit 1; }
si_banner() { printf '\n==> %s\n' "$*" >&2; }

# --- small predicates ------------------------------------------------------

si_have_cmd() { command -v "$1" >/dev/null 2>&1; }
si_is_root() { [[ $(id -u) -eq 0 ]]; }

# --- privileges ------------------------------------------------------------

# Run a command with root privileges (packages etc).
si_as_root() {
  if si_is_root; then
    "$@"
  elif si_have_cmd sudo; then
    sudo "$@"
  elif si_have_cmd doas; then
    doas "$@"
  else
    si_die "root privileges required and no sudo/doas available"
  fi
}

# The user whose environment we configure:
#  1. SHELL_INITS_USER (explicit, e.g. docker builds running as root for a user)
#  2. SUDO_USER (vm user running the script through sudo)
#  3. current user (root login / running as the user directly)
si_target_user() {
  if [[ -n ${SHELL_INITS_USER:-} ]]; then
    printf '%s' "$SHELL_INITS_USER"
  elif [[ -n ${SUDO_USER:-} ]]; then
    printf '%s' "$SUDO_USER"
  else
    id -un
  fi
}

si_target_home() {
  local user home
  user=$(si_target_user)
  home=$(getent passwd "$user" 2>/dev/null | cut -d: -f6 || true)
  [[ -n $home ]] || home=$HOME
  printf '%s' "$home"
}

# Run a shell command as the target user (git config, plugin clones, nvim...).
si_as_user() {
  local cmd=$1 target
  target=$(si_target_user)
  if [[ $target == $(id -un) ]]; then
    bash -c "$cmd"
  elif si_is_root; then
    su -s /bin/bash "$target" -c "$cmd"
  else
    si_die "cannot run as user '$target' without root privileges"
  fi
}

# Fix ownership of files we created as root for another user.
si_chown_target() {
  local target group
  target=$(si_target_user)
  [[ $target == $(id -un) ]] && return 0
  si_is_root || return 0
  group=$(id -gn "$target" 2>/dev/null || true)
  [[ -n $group ]] || group=$target
  chown -R "$target:$group" "$@"
}

# Create a directory as the target user (avoids root-owned ~/.local/... when
# provisioning another user's home).
si_user_mkdir() {
  local dir=$1
  if [[ $(si_target_user) == $(id -un) ]]; then
    mkdir -p "$dir"
  else
    si_as_user "mkdir -p '$dir'"
  fi
}

# --- component dependencies -------------------------------------------------

# Keep a one-time backup of a pre-existing config path.
si_backup_existing() {
  local path=$1 bak
  [[ -e $path ]] || return 0
  bak="${path}.pre-initkit"
  [[ -e $bak ]] && bak="${path}.pre-initkit.$(date +%s)"
  cp -a "$path" "$bak"
  si_warn "backed up existing $path -> $bak"
}

# Ensure another core initializer has run (checks its state marker).
si_ensure_core() {
  local component=$1 script
  if si_state_has "$component"; then
    return 0
  fi
  si_log "dependency core/${component}.sh not satisfied yet, running it"
  if [[ ${SI_MODE:-local} == local ]]; then
    script="$SI_ROOT/core/${component}.sh"
  else
    script=$(si_fetch_file "core/${component}.sh")
  fi
  bash "$script" || si_die "dependency component '${component}' failed"
}
