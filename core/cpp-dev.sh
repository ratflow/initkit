#!/usr/bin/env bash
# core/cpp-dev.sh - C++ development & debugging stack on top of core/neovim:
#   - build: cmake, ninja, gcc/g++, make, pkg-config
#   - dependencies: vcpkg (pinned release tag) at /opt/vcpkg, owned by the
#     target user, with VCPKG_ROOT/PATH wired into zsh (config/zsh/zshenv)
#   - code intelligence: clangd (+ clang-format, clang-tidy)
#   - compile_commands for non-cmake projects: bear
#   - debugging: codelldb (nvim-dap adapter) with its bundled lldb CLI +
#     liblldb, installed self-contained under /usr/local/lib/codelldb
#   - nvim: LazyVim clangd + dap + neotest/gtest layers deployed into
#     ~/.config/nvim/lua/plugins/cpp/ (see config/nvim/lua/plugins/cpp/)
#   - ~/cpp-sample: minimal cmake+vcpkg+gtest project, built during image
#     builds so containers work offline (vcpkg binary cache is prewarmed)
# Standalone: curl -fsSL <base>/core/cpp-dev.sh | bash -s -- --base-url <base>
# Env: SHELL_INITS_NVIM_BOOTSTRAP=1 -> strict mode for image builds: sync the
#      extra lazyvim plugins headlessly, verify them, build & test the sample
#      project; any failure is fatal (outside bootstrap they are warnings)
#
# Alpine notes (when adding lib/pkgmaps/alpine-*.sh): every step below is
# distro-neutral except (1) the pkgmap entries and (2) codelldb, which is a
# glibc binary - on musl use the `lldb` package's lldb-dap instead and point
# the nvim-dap adapter at it (config/nvim/lua/plugins/cpp/dap.lua). vcpkg
# works on alpine, but set VCPKG_FORCE_SYSTEM_BINARIES=1 when running as root.

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

CPP_DEV_REV=2
VCPKG_ROOT_DIR=/opt/vcpkg
STRICT=0
[[ ${SHELL_INITS_NVIM_BOOTSTRAP:-0} == 1 ]] && STRICT=1

si_banner "core/cpp-dev"
si_distro_detect
si_pkgmap_load

# optional pinning: versions.env next to the scripts
_v=$(si_try_fetch_file versions.env) && source "$_v"

_home=$(si_target_home)
_nvim_config=${_home}/.config/nvim

# the cpp-*.lua specs live inside the lazyvim config: if a neovim
# re-provision wiped them, run again even though the state marker matches
if si_state_has cpp-dev "$CPP_DEV_REV" \
  && si_have_cmd cmake && si_have_cmd clangd && si_have_cmd bear \
  && si_have_cmd lldb && si_have_cmd codelldb \
  && [[ -x ${VCPKG_ROOT_DIR}/vcpkg ]] \
  && [[ -f ${_nvim_config}/lua/plugins/cpp-clangd.lua ]]; then
  si_log "cpp-dev already initialized (rev ${CPP_DEV_REV}), skipping"
  exit 0
fi

# the nvim plugin layer lands inside the lazyvim config deployed by core/neovim
si_ensure_core neovim

# --- 1. distro toolchain ------------------------------------------------------
# libc6-dev is explicit: gcc pulls it only as a Recommends and
# --no-install-recommends would skip it (needed by vcpkg port builds).
# lldb comes bundled with codelldb below (adapter + liblldb + lldb CLI in one
# self-contained tree), so there is no separate distro lldb here
si_pkg_install git curl ca-certificates zip unzip tar \
  g++ gcc libc6-dev make pkg-config ninja cmake \
  clangd clang-format clang-tidy bear

# --- 2. codelldb (nvim-dap adapter + bundled lldb) -----------------------------
# the release ships a .vsix (zip) with extension/{adapter,lldb}: the adapter
# binary loads ../lldb/lib/liblldb.so relative to itself, so both trees are
# installed to /usr/local/lib/codelldb and exposed through symlinks. This also
# provides the `lldb` CLI - no distro lldb package needed, and the debugger
# version always matches the adapter. Asset naming differs from si_arch
# conventions (x64, not x86_64), hence the explicit mapping.
if ! si_have_cmd codelldb; then
  case $(uname -m) in
    x86_64)        _codelldb_asset='codelldb-linux-x64.vsix' ;;
    aarch64|arm64) _codelldb_asset='codelldb-linux-arm64.vsix' ;;
    *)             _codelldb_asset='' ;;
  esac
  if [[ -z $_codelldb_asset ]]; then
    si_warn "unsupported arch $(uname -m) for codelldb; skipping (nvim-dap will miss its adapter)"
  else
    _codelldb_tag=${CODELLDB_VERSION:-latest}
    [[ $_codelldb_tag == latest ]] && _codelldb_tag=$(si_gh_latest_tag vadimcn/codelldb)
    _codelldb_dir=/usr/local/lib/codelldb
    _tmp=$(mktemp -d)
    si_log "installing codelldb ${_codelldb_tag} (with bundled lldb)"
    si_fetch_raw "https://github.com/vadimcn/codelldb/releases/download/${_codelldb_tag}/${_codelldb_asset}" \
      >"${_tmp}/codelldb.zip" || si_die "codelldb download failed"
    unzip -qo "${_tmp}/codelldb.zip" -d "${_tmp}/x" || si_die "codelldb extraction failed"
    [[ -x "${_tmp}/x/extension/adapter/codelldb" && -f "${_tmp}/x/extension/lldb/lib/liblldb.so" ]] \
      || si_die "codelldb adapter or bundled lldb missing from ${_codelldb_asset}"
    si_as_root install -d -m 0755 "${_codelldb_dir}"
    si_as_root rm -rf "${_codelldb_dir}/adapter" "${_codelldb_dir}/lldb"
    si_as_root cp -a "${_tmp}/x/extension/adapter" "${_tmp}/x/extension/lldb" "${_codelldb_dir}/"
    si_as_root ln -sfn ../lib/codelldb/adapter/codelldb /usr/local/bin/codelldb
    si_as_root ln -sfn ../lib/codelldb/lldb/bin/lldb /usr/local/bin/lldb
    rm -rf "${_tmp}"
    unset _tmp _codelldb_asset _codelldb_tag _codelldb_dir
  fi
fi

# --- 3. vcpkg ------------------------------------------------------------------
# full history of the release branch (not a shallow clone): manifest baselines
# are resolved through git history; chown to the target user because vcpkg
# writes buildtrees/downloads under VCPKG_ROOT when building ports
if [[ ! -x ${VCPKG_ROOT_DIR}/vcpkg ]]; then
  _vcpkg_ref=${VCPKG_VERSION:-master}
  si_log "installing vcpkg (${_vcpkg_ref}) to ${VCPKG_ROOT_DIR}"
  si_as_root git clone -q --single-branch --branch "${_vcpkg_ref}" \
    https://github.com/microsoft/vcpkg "${VCPKG_ROOT_DIR}" \
    || si_die "vcpkg clone failed"
  si_as_root "${VCPKG_ROOT_DIR}/bootstrap-vcpkg.sh" -disableMetrics \
    || si_die "vcpkg bootstrap failed"
  si_chown_target "${VCPKG_ROOT_DIR}"
  unset _vcpkg_ref
fi
_vcpkg_ver=$(si_as_user "${VCPKG_ROOT_DIR}/vcpkg version" | head -n1 || true)

# --- 4. nvim plugin layer (lazyvim clangd + dap + neotest/gtest) ---------------
# files are flat cpp-*.lua specs: lazy.nvim imports lua/plugins/ one level deep
for _f in \
  bootstrap-cpp.lua \
  lua/plugins/cpp-clangd.lua \
  lua/plugins/cpp-dap.lua \
  lua/plugins/cpp-neotest.lua
do
  [[ -f "${_nvim_config}/${_f}" ]] && continue
  si_deploy_file "config/nvim/${_f}" "${_nvim_config}/${_f}"
done
unset _f

# --- 5. sample project ----------------------------------------------------------
_sample=${_home}/cpp-sample
for _f in \
  CMakeLists.txt \
  CMakePresets.json \
  vcpkg.json \
  .clang-format \
  README.md \
  include/calc.hpp \
  src/calc.cpp \
  src/main.cpp \
  tests/test_calc.cpp
do
  [[ -e "${_sample}/${_f}" ]] && continue
  si_deploy_file "config/cpp-sample/${_f}" "${_sample}/${_f}"
done
unset _f

cpp_dev_build_sample() {
  si_as_user "cd '${_sample}' && VCPKG_ROOT='${VCPKG_ROOT_DIR}' cmake --preset debug \
    && VCPKG_ROOT='${VCPKG_ROOT_DIR}' cmake --build --preset debug \
    && ln -sfn build/debug/compile_commands.json compile_commands.json \
    && ctest --preset debug"
}

cpp_dev_seed_neotest_gtest() {
  # pre-map the project (and its test file) -> the gtest binary so neotest
  # works without a manual :ConfigureGtest round-trip. Storage format of
  # neotest-gtest at the pinned commit: one JSON per adapter ROOT dir,
  # ~/.local/share/nvim/neotest-gtest/<path with / -> %0>.json, mapping
  # neotest node ids (root dir, test files) to executables
  [[ -x ${_sample}/build/debug/unit_tests ]] || return 0
  local root encoded store
  root=${_sample}
  encoded=$(printf '%s' "$root" | sed 's/%/%1/g; s|/|%0|g')
  store=${_home}/.local/share/nvim/neotest-gtest
  si_user_mkdir "$store"
  printf '{"node2executable":{"%s":"%s","%s/tests/test_calc.cpp":"%s"}}' \
    "$root" "${_sample}/build/debug/unit_tests" \
    "$root" "${_sample}/build/debug/unit_tests" \
    >"${store}/${encoded}.json"
  si_chown_target "$store"
}

if (( STRICT )); then
  # image build: everything below must succeed so the image works offline
  si_log "strict mode: syncing lazyvim cpp plugins headlessly"
  si_as_user 'nvim --headless "+Lazy! sync" +qa' \
    || si_die "headless plugin sync failed"
  si_as_user 'nvim --headless "+lua dofile(vim.fn.stdpath(\"config\")..\"/bootstrap-cpp.lua\")" +qa' \
    || si_die "cpp layer plugin verification failed (see output above)"
  # pre-install lazyvim's default mason tools so the first offline start is quiet
  si_as_user 'nvim --headless "+MasonInstall --sync stylua shfmt" +qa' \
    || si_warn "mason pre-install of stylua/shfmt failed (cosmetic)"
  si_log "strict mode: building + testing the sample project (also prewarms the vcpkg binary cache)"
  cpp_dev_build_sample || si_die "sample project build failed"
  cpp_dev_seed_neotest_gtest
else
  # interactive/VM run: the sample build needs network the first time (vcpkg
  # downloads gtest); treat it as a best-effort verification
  cpp_dev_build_sample \
    || si_warn "sample project build failed (first build needs network for vcpkg dependencies)"
  cpp_dev_seed_neotest_gtest || true
fi

si_state_mark cpp-dev "$CPP_DEV_REV"
si_log "cpp-dev ready: $(cmake --version | head -n1 | cut -d' ' -f3) cmake," \
  "clangd $(clangd --version | head -n1 | grep -o '[0-9][0-9.]*' | head -n1)," \
  "codelldb, lldb, bear, ${_vcpkg_ver:-vcpkg}"
