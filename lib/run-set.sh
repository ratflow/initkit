# lib/run-set.sh - shared runner used by sets/<name>.sh wrappers
# The set wrapper defines SET_NAME and COMPONENTS, then calls si_run_set.

si_run_core() {
  local component=$1 script
  if [[ ${SI_MODE:-local} == local ]]; then
    script="$SI_ROOT/core/${component}.sh"
    [[ -f $script ]] || si_die "unknown component '${component}' (no ${script})"
  else
    script=$(si_fetch_file "core/${component}.sh")
  fi
  si_banner "component: ${component}"
  SI_COMPONENT=$component bash "$script" || si_die "component '${component}' failed"
}

si_run_set() {
  local component skip
  local -a skips=()
  if [[ -n ${SHELL_INITS_SKIP:-} ]]; then
    IFS=',' read -r -a skips <<<"$SHELL_INITS_SKIP"
  fi
  for component in "${COMPONENTS[@]}"; do
    for skip in "${skips[@]:-}"; do
      [[ $component == "$skip" ]] && continue 2
    done
    si_run_core "$component"
  done
}

# --- common post hooks ------------------------------------------------------

# Make zsh the login shell of the target user (best effort).
si_set_default_shell_zsh() {
  local target shell zsh_bin
  target=$(si_target_user)
  shell=$(getent passwd "$target" | cut -d: -f7)
  if [[ $shell == *zsh ]]; then
    si_log "login shell of '${target}' is already zsh"
    return 0
  fi
  zsh_bin=$(command -v zsh || true)
  [[ -n $zsh_bin ]] || { si_warn "zsh not found, cannot set default shell"; return 0; }
  if si_is_root; then
    usermod -s "$zsh_bin" "$target" 2>/dev/null \
      || chsh -s "$zsh_bin" "$target" 2>/dev/null \
      || si_warn "failed to change login shell for '${target}'"
  elif si_have_cmd sudo; then
    sudo chsh -s "$zsh_bin" "$target" 2>/dev/null \
      || sudo usermod -s "$zsh_bin" "$target" 2>/dev/null \
      || si_warn "failed to change login shell for '${target}'"
  else
    si_warn "no root privileges; run 'chsh -s ${zsh_bin}' manually"
  fi
}

si_print_summary() {
  local tool
  printf '\n==> %s complete\n' "${SET_NAME:-initkit}"
  for tool in zsh tmux fzf nvim lazygit cmake clangd bear lldb codelldb vcpkg; do
    if si_have_cmd "$tool"; then
      printf '    %-8s %s\n' "$tool" "$(command -v "$tool")"
    fi
  done
  printf '==> next: start a new login shell (zsh), then run: tmux new -As main\n\n'
}
