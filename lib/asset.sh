# lib/asset.sh - install prebuilt binaries from GitHub releases
# Asset pattern placeholders: {tag}=full tag (v1.2.3), {ver}=tag without 'v',
# {arch}=x86_64 | arm64 (aarch64 is mapped to arm64, the common release naming).

si_arch() {
  case $(uname -m) in
    x86_64)  printf x86_64 ;;
    aarch64 | arm64) printf arm64 ;;
    *) si_die "unsupported architecture: $(uname -m)" ;;
  esac
}

si_gh_latest_tag() {
  local repo=$1 url tag
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${repo}/releases/latest") \
    || si_die "failed to resolve latest release of ${repo}"
  tag=${url##*/}
  [[ -n $tag ]] || si_die "could not parse latest tag for ${repo}"
  printf '%s' "$tag"
}

# si_install_bin <file> - install an executable to /usr/local/bin when
# possible, otherwise to the target user's ~/.local/bin.
si_install_bin() {
  local src=$1 name dest dir
  name=$(basename "$src")
  if si_is_root || si_have_cmd sudo; then
    dest="/usr/local/bin/${name}"
    si_as_root install -m 0755 "$src" "$dest"
  else
    dir="$(si_target_home)/.local/bin"
    mkdir -p "$dir"
    install -m 0755 "$src" "$dir/$name"
    si_chown_target "$dir"
    dest="$dir/$name"
  fi
  si_log "installed binary: $dest"
}

# si_asset_github <owner/repo> <version|latest> <asset-pattern> [checksums-file]
# Downloads, verifies (when a checksums file is given), extracts and installs
# the single executable contained in the asset.
si_asset_github() {
  local repo=$1 version=$2 pattern=$3 checksums=${4:-}
  local arch tag base asset tmp want candidate cks

  arch=$(si_arch)
  if [[ $version == latest ]]; then
    tag=$(si_gh_latest_tag "$repo")
  else
    tag=$version
  fi
  base="https://github.com/${repo}/releases/download/${tag}"
  asset=$pattern
  asset=${asset//\{tag\}/$tag}
  asset=${asset//\{ver\}/${tag#v}}
  asset=${asset//\{arch\}/$arch}

  tmp=$(mktemp -d)
  si_log "downloading ${repo} ${tag} (${asset})"
  si_fetch_raw "${base}/${asset}" >"${tmp}/${asset}" || si_die "download failed: ${asset}"

  if [[ -n $checksums ]]; then
    cks=$(basename "$checksums")
    si_fetch_raw "${base}/${checksums}" >"${tmp}/${cks}" || si_die "checksums download failed"
    (cd "$tmp" && grep " ${asset}\$" "$cks" | sha256sum -c - >/dev/null) \
      || si_die "checksum mismatch for ${asset}"
    si_log "checksum verified: ${asset}"
  fi

  case $asset in
    *.tar.gz | *.tgz) tar -xzf "${tmp}/${asset}" -C "$tmp" ;;
    *.zip)            unzip -qo "${tmp}/${asset}" -d "$tmp" ;;
    *.gz)             gzip -dc "${tmp}/${asset}" >"${tmp}/${repo##*/}" \
                        && chmod +x "${tmp}/${repo##*/}" ;;
    *)                mv "${tmp}/${asset}" "${tmp}/binary" ;;
  esac

  want=${repo##*/}
  candidate=$(find "$tmp" -maxdepth 3 -type f -name "$want" -perm -u+x | head -n1)
  [[ -n $candidate ]] || candidate=$(find "$tmp" -maxdepth 3 -type f -perm -u+x | head -n1)
  [[ -n $candidate ]] || si_die "no executable found inside ${asset}"
  si_install_bin "$candidate"
  rm -rf "$tmp"
  printf '%s\n' "${tag#v}"
}
