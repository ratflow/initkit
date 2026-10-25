# lib/state.sh - idempotency markers (which components are already installed)
# State lives in the target user's state dir; first line = version/rev marker.

si_state_root() {
  printf '%s/initkit' "${XDG_STATE_HOME:-$(si_target_home)/.local/state}"
}

si_state_file() {
  printf '%s/%s.ver' "$(si_state_root)" "$1"
}

# si_state_has <component> [revision]
# True when the marker exists and matches the revision (any revision if omitted).
# SHELL_INITS_FORCE=1 or SI_FORCE=1 always returns false (reinstall).
si_state_has() {
  local component=$1 revision=${2:-} file
  [[ -n ${SI_FORCE:-${SHELL_INITS_FORCE:-}} ]] && return 1
  file=$(si_state_file "$component")
  [[ -f $file ]] || return 1
  if [[ -n $revision ]]; then
    [[ $(head -n1 "$file") == "$revision" ]] || return 1
  fi
  return 0
}

# si_state_mark <component> <revision>
si_state_mark() {
  local component=$1 revision=$2 file
  file=$(si_state_file "$component")
  si_user_mkdir "$(dirname "$file")"
  printf '%s\ninstalled=%s distro=%s\n' \
    "$revision" "$(date -u +%FT%TZ)" "${SI_DISTRO_SLUG:-unknown}" >"$file"
  si_chown_target "$file"
  si_log "marked ${component} as initialized (rev ${revision})"
}
