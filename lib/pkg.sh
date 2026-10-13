# lib/pkg.sh - package installation abstraction (apt/apk dispatch via pkgmaps)
# Requires SI_DISTRO_SLUG. The pkgmap defines: declare -A PKG (abstract -> real).

si_pkgmap_load() {
  local map
  map=$(si_fetch_file "lib/pkgmaps/${SI_DISTRO_SLUG}.sh")
  # shellcheck disable=SC1090
  source "$map" || si_die "failed to load pkgmap for ${SI_DISTRO_SLUG}"
  si_log "loaded pkgmap for ${SI_DISTRO_SLUG}"
}

# Refresh the package index once per process.
si_pkg_update() {
  [[ -n ${SI_PKG_UPDATED:-} ]] && return 0
  case ${SI_PKG_MANAGER:?pkg manager not detected} in
    apt) si_as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq ;;
    apk) si_as_root apk update -q ;;
    *) si_die "unknown package manager: $SI_PKG_MANAGER" ;;
  esac
  SI_PKG_UPDATED=1
}

# si_pkg_install <abstract-name>... (names resolved through the pkgmap)
si_pkg_install() {
  (( $# > 0 )) || return 0
  si_pkg_update
  local -a real=()
  local abstract mapped
  for abstract in "$@"; do
    mapped=${PKG[$abstract]:-}
    if [[ -z $mapped ]]; then
      si_warn "no pkgmap entry for '$abstract', using the name as-is"
      mapped=$abstract
    fi
    real+=("$mapped")
  done
  si_log "installing packages: ${real[*]}"
  case $SI_PKG_MANAGER in
    apt)
      si_as_root env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y -qq --no-install-recommends "${real[@]}"
      ;;
    apk)
      si_as_root apk add -q "${real[@]}"
      ;;
    *)
      si_die "unknown package manager: $SI_PKG_MANAGER" ;;
  esac
}
