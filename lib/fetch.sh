# lib/fetch.sh - fetch files relative to the base URL (or read from a checkout)
# Requires SI_MODE/SI_ROOT/SI_BASE_URL from the entry preamble.

# Print a URL to stdout (curl preferred, wget fallback).
si_fetch_raw() {
  local url=$1
  if si_have_cmd curl; then
    curl -fsSL "$url"
  elif si_have_cmd wget; then
    wget -qO- "$url"
  else
    si_die "neither curl nor wget available"
  fi
}

# si_fetch_file <relpath>  -> prints a local path to the file (dies on failure)
si_fetch_file() {
  local rel=$1 out
  if [[ ${SI_MODE:-local} == local ]]; then
    out="$SI_ROOT/$rel"
    [[ -f $out ]] || si_die "file missing from checkout: $out"
  else
    out=$(mktemp)
    si_fetch_raw "${SI_BASE_URL%/}/$rel" >"$out" || si_die "failed to fetch $rel"
  fi
  printf '%s' "$out"
}

# si_try_fetch_file <relpath> -> prints path or nothing if unavailable
si_try_fetch_file() {
  local rel=$1
  if [[ ${SI_MODE:-local} == local ]]; then
    [[ -f "$SI_ROOT/$rel" ]] && printf '%s' "$SI_ROOT/$rel"
  else
    local out
    out=$(mktemp)
    if si_fetch_raw "${SI_BASE_URL%/}/$rel" >"$out" 2>/dev/null; then
      printf '%s' "$out"
    else
      rm -f "$out"
    fi
  fi
}

# si_fetch <relpath> -> file contents on stdout
si_fetch() {
  local path
  path=$(si_fetch_file "$1")
  cat "$path"
}

# si_deploy_file <relpath> <absolute-dest-path>
si_deploy_file() {
  local src dest
  src=$(si_fetch_file "$1")
  dest=$2
  si_user_mkdir "$(dirname "$dest")"
  cp "$src" "$dest"
  si_chown_target "$dest"
  si_log "deployed $1 -> $dest"
}
