#!/usr/bin/env bash
# tools/set-hybrid-theme.sh - switch an initkit-provisioned environment from
# the default catppuccin look to the hybrid/gruvbox setup used on the host.
#
# What it does:
#   neovim: comments out the current lua/plugins/colorscheme.lua contents and
#           activates chodak166/nvim-hybrid-theme exactly as configured on the
#           host, then best-effort syncs plugins headlessly (lazy.nvim would
#           also install it on the next start)
#   tmux:   optionally (asks) comments out the pastel status theme in
#           ~/.tmux.conf and activates tmux-gruvbox (dark) from
#           ~/.tmux.d/tmux-gruvbox; reloads the running tmux server if any
#
# Backups (one-time, never overwritten): colorscheme.lua.pre-hybrid,
# .tmux.conf.pre-hybrid. Re-running the script is a no-op once the themes
# are active.
#
# Usage:
#   ./tools/set-hybrid-theme.sh
#   curl -fsSL https://raw.githubusercontent.com/ratflow/initkit/master/tools/set-hybrid-theme.sh | bash
#
# Standalone on purpose: needs only bash + coreutils (+ git or curl/wget for
# the tmux plugin), no repository checkout (safe to pipe from curl).

set -euo pipefail

GRUVBOX_REPO="https://github.com/egel/tmux-gruvbox"
GRUVBOX_DIR="$HOME/.tmux.d/tmux-gruvbox"

log()  { printf '[initkit] %s\n' "$*" >&2; }
warn() { printf '[initkit][warn] %s\n' "$*" >&2; }
die()  { printf '[initkit][error] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
set-hybrid-theme - switch an initkit environment to the host's hybrid theme.

usage: tools/set-hybrid-theme.sh [options]

options:
  --nvim-colorscheme <file>  colorscheme.lua to rewrite
                             (default: ~/.config/nvim/lua/plugins/colorscheme.lua)
  --tmux-conf <file>         tmux config to rewrite (default: ~/.tmux.conf)
  --gruvbox-dir <dir>        where to install tmux-gruvbox
                             (default: ~/.tmux.d/tmux-gruvbox)
  --no-tmux                  do not ask about/switch the tmux theme
  --no-sync                  skip the headless plugin sync
  -h, --help                 show this help
USAGE
}

ask_yn() { # $1 question, $2 default (y|n); returns 0 for yes
  local answer=""
  printf '%s [%s] ' "$1" "$([ "$2" = y ] && printf 'Y/n' || printf 'y/N')" >&2
  if [ -r /dev/tty ]; then
    IFS= read -r answer 2>/dev/null </dev/tty || answer=""
  else
    printf '\n' >&2
    return 1
  fi
  [ -z "$answer" ] && answer=$2
  case $answer in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

has_tty() { [ -r /dev/tty ]; }

NVIM_COLORSHEME="$HOME/.config/nvim/lua/plugins/colorscheme.lua"
TMUX_CONF="$HOME/.tmux.conf"
DO_TMUX=1
DO_SYNC=1

while [ $# -gt 0 ]; do
  case $1 in
    --nvim-colorscheme) NVIM_COLORSHEME=${2:?--nvim-colorscheme needs a value}; shift 2 ;;
    --tmux-conf)        TMUX_CONF=${2:?--tmux-conf needs a value}; shift 2 ;;
    --gruvbox-dir)      GRUVBOX_DIR=${2:?--gruvbox-dir needs a value}; shift 2 ;;
    --no-tmux)          DO_TMUX=0; shift ;;
    --no-sync)          DO_SYNC=0; shift ;;
    -h|--help)          usage; exit 0 ;;
    *)                  die "unknown option: $1 (see --help)" ;;
  esac
done

# comment out every line of $1 (lua: "-- ", shell: "# "; empty lines stay empty)
comment_file() { # $1=file $2=comment-prefix
  local _f=${1:?} _p=${2:?} _out
  _out=$(mktemp)
  while IFS= read -r _line || [ -n "${_line:-}" ]; do
    if [ -z "$_line" ]; then printf '\n' >>"$_out"; else printf '%s %s\n' "$_p" "$_line" >>"$_out"; fi
  done <"$_f"
  cat "$_out" >"$_f"
  rm -f "$_out"
  unset _f _p _out _line
}

# comment out the `# --- pastel theme` section of the deployed tmux.conf:
# from its header line until the next `# ---` section header or EOF
comment_pastel_section() { # $1=file
  local _f=${1:?} _out _in_section=0
  _out=$(mktemp)
  while IFS= read -r _line || [ -n "${_line:-}" ]; do
    case $_line in
      "# --- pastel theme"*) _in_section=1 ;;
      "# --- "*) [ "$_in_section" = 1 ] && _in_section=0 ;;
    esac
    if [ "$_in_section" = 1 ] && [ -n "$_line" ] && [[ $_line != \#* ]]; then
      printf '# %s\n' "$_line" >>"$_out"
    else
      printf '%s\n' "$_line" >>"$_out"
    fi
  done <"$_f"
  cat "$_out" >"$_f"
  rm -f "$_out"
  unset _f _out _line _in_section
}

backup_once() { # $1=file -> $1.pre-hybrid
  [ -e "$1.pre-hybrid" ] && return 0
  cp "$1" "$1.pre-hybrid" || die "cannot back up $1"
  log "backup: $1.pre-hybrid"
}

# --- neovim: hybrid theme ------------------------------------------------------

if grep -qE '^[[:space:]]*"chodak166/nvim-hybrid-theme"' "$NVIM_COLORSHEME" 2>/dev/null; then
  log "neovim hybrid theme already active, skipping"
else
  [ -f "$NVIM_COLORSHEME" ] || die "no colorscheme.lua at $NVIM_COLORSHEME (is this an initkit-provisioned machine?)"
  backup_once "$NVIM_COLORSHEME"
  comment_file "$NVIM_COLORSHEME" "--"
  cat >>"$NVIM_COLORSHEME" <<'LUA'
return {
  {
    "chodak166/nvim-hybrid-theme",
    name = "hybrid-theme",
    lazy = false,
    priority = 1000,
    config = function()
      require("hybrid-theme").setup({
        background_variant = "semi_flat",
      })
      require("hybrid-theme").colorscheme()
    end,
  },
}
LUA
  log "neovim theme switched to chodak166/nvim-hybrid-theme ($NVIM_COLORSHEME)"

  if [ "$DO_SYNC" = 1 ] && command -v nvim >/dev/null 2>&1; then
    log "syncing plugins headlessly (needs network once)..."
    if ! nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1; then
      warn "headless plugin sync failed; lazy.nvim will install the theme on the next start"
    fi
  fi
fi

# --- tmux: gruvbox theme (optional) ---------------------------------------------

if [ "$DO_TMUX" = 1 ]; then
  if [ -f "$TMUX_CONF" ] && grep -qE '^[[:space:]]*run[[:space:]].*tmux-gruvbox' "$TMUX_CONF"; then
    log "tmux gruvbox theme already active, skipping"
  elif ! has_tty; then
    warn "no tty available to ask about the tmux theme; skipped (use --no-tmux to silence)"
  elif ask_yn "Also switch the tmux theme to tmux-gruvbox (dark), as on the host?" y; then
    [ -f "$TMUX_CONF" ] || die "no tmux.conf at $TMUX_CONF"

    if [ ! -f "$GRUVBOX_DIR/gruvbox-tpm.tmux" ]; then
      log "installing tmux-gruvbox into $GRUVBOX_DIR ..."
      mkdir -p "$(dirname "$GRUVBOX_DIR")"
      _tmpd=$(mktemp -d)
      if command -v git >/dev/null 2>&1; then
        git clone --depth 1 "$GRUVBOX_REPO" "$GRUVBOX_DIR" >/dev/null 2>&1 \
          || die "git clone of $GRUVBOX_REPO failed"
      elif command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        _tar="$_tmpd/gruvbox.tar.gz"
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL "${GRUVBOX_REPO}/archive/refs/heads/main.tar.gz" -o "$_tar" \
            || die "download of tmux-gruvbox failed"
        else
          wget -qO "$_tar" "${GRUVBOX_REPO}/archive/refs/heads/main.tar.gz" \
            || die "download of tmux-gruvbox failed"
        fi
        tar -xzf "$_tar" -C "$_tmpd" || die "cannot unpack tmux-gruvbox"
        mv "$_tmpd"/tmux-gruvbox-* "$GRUVBOX_DIR" || die "cannot install tmux-gruvbox"
      else
        die "tmux-gruvbox needs git or curl/wget, none found"
      fi
      rm -rf "$_tmpd"
      unset _tmpd _tar
    fi

    backup_once "$TMUX_CONF"
    comment_pastel_section "$TMUX_CONF"
    _run_line="run ${GRUVBOX_DIR/#$HOME/\~}/gruvbox-tpm.tmux"
    cat >>"$TMUX_CONF" <<CONF
# --- gruvbox theme (tmux-gruvbox) ------------------------------------------------
${_run_line}
set -g @tmux-gruvbox 'dark' # or 'dark256', 'light', 'light256'
CONF
    unset _run_line
    log "tmux theme switched to tmux-gruvbox (dark) ($TMUX_CONF)"

    if command -v tmux >/dev/null 2>&1 && tmux info >/dev/null 2>&1; then
      if tmux source-file "$TMUX_CONF" 2>/dev/null; then
        log "running tmux server reloaded"
      else
        warn "could not reload the running tmux server; restart tmux or run: tmux source-file $TMUX_CONF"
      fi
    fi
  else
    log "tmux theme left unchanged"
  fi
fi

log "done"
