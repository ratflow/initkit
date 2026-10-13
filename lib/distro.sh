# lib/distro.sh - detect the target distro, reject unsupported ones
# Sets: SI_DISTRO_SLUG (e.g. ubuntu-26.04), SI_PKG_MANAGER (apt|apk)

si_distro_detect() {
  [[ -r /etc/os-release ]] || si_die "cannot read /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  local slug="${ID}-${VERSION_ID}"
  unset ID VERSION_ID NAME PRETTY_NAME VERSION_ID VERSION 2>/dev/null || true

  case $slug in
    ubuntu-26.04) SI_DISTRO_SLUG=$slug; SI_PKG_MANAGER=apt ;;
    *)
      si_die "unsupported distro '${slug}'. Supported: ubuntu-26.04. \
To support another distro add lib/pkgmaps/${slug}.sh and extend lib/distro.sh."
      ;;
  esac
  export SI_DISTRO_SLUG SI_PKG_MANAGER
  si_log "detected distro: $SI_DISTRO_SLUG (pkg manager: $SI_PKG_MANAGER)"
}
