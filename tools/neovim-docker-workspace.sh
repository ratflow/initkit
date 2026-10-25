#!/usr/bin/env bash
# tools/neovim-docker-workspace.sh - open the current project inside an initkit
# dev container and edit it with the HOST's neovim/LazyVim setup.
#
# Generates a self-contained workspace script (./.nvim-docker-workspace.sh) in
# the project directory and runs it:
#   - the project directory is mounted at /workspace in the container
#   - the host's ~/.config/nvim and ~/.local/share/nvim are mounted over the
#     container's, so the exact editor setup from the host runs against the
#     image's toolchain (clangd, lldb, gcc, vcpkg, ...); clangd and the build
#     tools see plain /workspace paths, nothing to remap or configure
#   - per-project docker volumes keep nvim data/state/cache, so shada and undo
#     history survive container restarts
#   - the container user is remapped to the host uid/gid on first start, so
#     file ownership works in both directions without root in the project
#   - re-running the workspace script returns to the same container; a tmux
#     detach leaves it running (Enter reattaches, Ctrl-d stops it)
#
# Usage:
#   cd my/project
#   curl -fsSL https://raw.githubusercontent.com/ratflow/initkit/master/tools/neovim-docker-workspace.sh | bash
#   # with options, append:  | bash -s -- --image initkit/zsh-tmux-neovim:ubuntu-26.04
#
# Standalone on purpose: needs only docker + coreutils, no repository checkout
# (safe to pipe from curl).

set -euo pipefail

DEFAULT_IMAGE="initkit/dev-cpp-neovim:ubuntu-26.04"
SCRIPT_FILENAME=".nvim-docker-workspace.sh"

log()  { printf '[initkit] %s\n' "$*" >&2; }
warn() { printf '[initkit][warn] %s\n' "$*" >&2; }
die()  { printf '[initkit][error] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
neovim-docker-workspace - edit the current project in an initkit dev container
using the host's neovim/LazyVim setup.

usage: tools/neovim-docker-workspace.sh [options]

options:
  --image <ref>      image to use (default: $NVIM_DOCKER_IMAGE or
                     initkit/dev-cpp-neovim:ubuntu-26.04)
  --dir <path>       project directory to mount as /workspace (default: .)
  --name <name>      container name (default: initkit-nvim-<dir>-<hash>)
  --data             always share the host's ~/.local/share/nvim with the
                     container (default when host and image neovim match)
  --no-data          never share it; the container keeps its own plugins in a
                     per-project volume and syncs them to the host's
                     lazy-lock.json on first start (needs network once,
                     immune to neovim version drift)
  --ssh              mount ~/.ssh into the container read-only
  --forward-agent    forward the ssh agent socket (SSH_AUTH_SOCK); if the
                     socket path changes later (re-login/reboot), recreate
                     the container: docker rm <name>
  --no-check         skip the host-vs-image neovim version and arch checks
  --no-run           only generate the workspace script, do not start it
  -h, --help         show this help

Generates <dir>/.nvim-docker-workspace.sh and runs it. The generated script
attaches to the project container if it exists, starts it if stopped, creates
it on first use. Regenerating is safe; changes take effect after recreating
the container (docker rm <name>).
USAGE
}

ask_yn() { # $1 question, $2 default (y|n); returns 0 for yes
  local answer=""
  printf '%s [%s] ' "$1" "$([ "$2" = y ] && printf 'Y/n' || printf 'y/N')" >&2
  if [ -r /dev/tty ]; then
    IFS= read -r answer 2>/dev/null </dev/tty || answer=""
  fi
  [ -z "$answer" ] && answer=$2
  case $answer in
    y|Y|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

hash8() { # deterministic short hash of $1 (sha256 -> shasum -> cksum)
  local out=""
  out=$(printf %s "$1" | sha256sum 2>/dev/null || true)
  [ -n "$out" ] || out=$(printf %s "$1" | shasum -a 256 2>/dev/null || true)
  [ -n "$out" ] || out=$(printf %s "$1" | cksum 2>/dev/null || true)
  [ -n "$out" ] || die "no hashing tool found (sha256sum/shasum/cksum)"
  printf '%s' "$out" | awk '{print $1}' | cut -c1-8
}

nvim_stdpath() { # $1 = config|data; prints the host path (empty if unknown)
  local bin
  bin=$(command -v nvim 2>/dev/null || true)
  [ -n "$bin" ] || return 0
  "$bin" --headless -u NONE "+lua print(vim.fn.stdpath('$1'))" +qa 2>/dev/null | tail -n 1 || true
}

IMAGE=""
DIR=""
NAME_OVERRIDE=""
DATA_MODE="auto" # auto | yes | no
MOUNT_SSH=0
FORWARD_AGENT=0
CHECK=1
RUN=1

while [ $# -gt 0 ]; do
  case $1 in
    --image)        IMAGE=${2:?--image needs a value}; shift 2 ;;
    --dir)          DIR=${2:?--dir needs a value}; shift 2 ;;
    --name)         NAME_OVERRIDE=${2:?--name needs a value}; shift 2 ;;
    --data)         DATA_MODE=yes; shift ;;
    --no-data)      DATA_MODE=no; shift ;;
    --ssh)          MOUNT_SSH=1; shift ;;
    --forward-agent) FORWARD_AGENT=1; shift ;;
    --no-check)     CHECK=0; shift ;;
    --no-run)       RUN=0; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown option: $1 (see --help)" ;;
  esac
done

command -v docker >/dev/null 2>&1 || die "docker is not available"
docker info >/dev/null 2>&1 || die "docker daemon is not reachable"
[ -n "$IMAGE" ] || IMAGE=${NVIM_DOCKER_IMAGE:-$DEFAULT_IMAGE}

WORKSPACE=$(cd -- "${DIR:-.}" 2>/dev/null && pwd -P) || die "cannot access directory: ${DIR:-.}"
[ -w "$WORKSPACE" ] || die "directory is not writable: $WORKSPACE"

HOST_UID=$(id -u)
HOST_GID=$(id -g)

# --- host editor paths -------------------------------------------------------

NVIM_CONFIG=$(nvim_stdpath config)
[ -n "$NVIM_CONFIG" ] || NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA=$(nvim_stdpath data)
[ -n "$NVIM_DATA" ] || NVIM_DATA="$HOME/.local/share/nvim"

if [ ! -d "$NVIM_CONFIG" ]; then
  warn "no host neovim config at $NVIM_CONFIG; the container will use its baked-in one"
  NVIM_CONFIG=""
  NVIM_DATA=""
fi
if [ -n "$NVIM_DATA" ] && [ ! -d "$NVIM_DATA" ]; then
  warn "no host neovim data dir at $NVIM_DATA; the container keeps its baked-in plugins"
  NVIM_DATA=""
fi

GITCONFIG=""
if [ -f "$HOME/.gitconfig" ]; then
  GITCONFIG=$HOME/.gitconfig
  if command -v readlink >/dev/null 2>&1; then
    _resolved=$(readlink -f "$GITCONFIG" 2>/dev/null || true)
    if [ -n "$_resolved" ] && [ -f "$_resolved" ]; then GITCONFIG=$_resolved; fi
  fi
fi
unset _resolved

# --- image checks ------------------------------------------------------------

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  log "image '$IMAGE' not present locally, pulling..."
  if ! docker pull "$IMAGE" >/dev/null 2>&1; then
    warn "could not pull '$IMAGE'; local initkit images:"
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^initkit/' | sed 's/^/    /' >&2 || true
    die "build one with dockerfiles/<set>.build.sh, or pass --image"
  fi
fi

HOST_NVIM_VER=$(nvim --version 2>/dev/null | head -n 1 | sed -n 's/^NVIM v\([0-9][0-9.]*\).*/\1/p' || true)
IMG_NVIM_VER=""
if [ "$CHECK" = 1 ]; then
  _img_line=$(docker run --rm --entrypoint /bin/sh "$IMAGE" \
    -c 'command -v nvim >/dev/null 2>&1 && nvim --version | head -n 1' 2>/dev/null | head -n 1 || true)
  IMG_NVIM_VER=$(printf '%s' "$_img_line" | sed -n 's/^NVIM v\([0-9][0-9.]*\).*/\1/p')
  unset _img_line
  _img_arch=$(docker image inspect -f '{{.Architecture}}' "$IMAGE" 2>/dev/null || true)
  case $(uname -m) in
    x86_64)      _host_arch=amd64 ;;
    aarch64|arm64) _host_arch=arm64 ;;
    *)           _host_arch=$(uname -m) ;;
  esac
  if [ -n "$_img_arch" ] && [ "$_img_arch" != "$_host_arch" ]; then
    warn "host arch ($_host_arch) != image arch ($_img_arch); everything runs under emulation (slow)"
  fi
  unset _img_arch _host_arch
fi

# --- plugin data sharing decision --------------------------------------------

if [ "$DATA_MODE" = auto ]; then
  DATA_MODE=yes
  if [ -n "$HOST_NVIM_VER" ] && [ -n "$IMG_NVIM_VER" ] && [ "$HOST_NVIM_VER" != "$IMG_NVIM_VER" ]; then
    warn "host neovim v$HOST_NVIM_VER != image neovim v$IMG_NVIM_VER"
    warn "shared plugin data (treesitter parsers, mason binaries) may be built for the other version"
    if ask_yn "Share the host's ~/.local/share/nvim anyway?" n; then
      log "host plugin data will be shared as requested"
    else
      DATA_MODE=no
    fi
  fi
fi
if [ "$DATA_MODE" != yes ]; then
  NVIM_DATA=""
fi
if [ "$DATA_MODE" = no ] && [ -n "$NVIM_CONFIG" ]; then
  log "plugin data: per-project container volume; LazyVim syncs to your lazy-lock.json on first start (:Lazy restore pins exact versions)"
fi

# --- container name ----------------------------------------------------------

if [ -n "$NAME_OVERRIDE" ]; then
  NAME=$NAME_OVERRIDE
  case $NAME in
    *[!a-zA-Z0-9_.-]*|[!a-zA-Z0-9]*) die "invalid container name: $NAME" ;;
  esac
else
  _base=$(basename "$WORKSPACE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' \
    | sed -e 's/^[^a-z0-9]*//' -e 's/[^a-z0-9]*$//' | cut -c1-24)
  [ -n "$_base" ] || _base=workspace
  NAME="initkit-nvim-$_base-$(hash8 "$WORKSPACE")"
  unset _base
fi

if docker container inspect "$NAME" >/dev/null 2>&1; then
  warn "container '$NAME' already exists and keeps its original settings"
  warn "to apply changes: docker rm '$NAME', then rerun the generator"
fi

# --- generate the workspace script -------------------------------------------

TARGET="$WORKSPACE/$SCRIPT_FILENAME"

{
  echo '#!/usr/bin/env bash'
  echo "# Generated by initkit tools/neovim-docker-workspace.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ) - do not edit, regenerate instead."
  cat <<'HEADER'
# Returns to this project's initkit container: attaches if running, starts it
# if stopped, creates it on first use. The container mounts this directory at
# /workspace, your host neovim config (and optionally plugin data), and runs
# the image's toolchain.
#
#   tmux detach (prefix d) -> container keeps running: Enter reattaches,
#                             Ctrl-d stops it (rerun this file to return)
#   plain shell            -> docker exec -it -u dev CONTAINER zsh -l
#   reset                  -> docker rm CONTAINER, then rerun the generator
HEADER
  echo
  printf 'IMAGE=%q\n' "$IMAGE"
  printf 'NAME=%q\n' "$NAME"
  printf 'WORKSPACE=%q\n' "$WORKSPACE"
  printf 'NVIM_CONFIG=%q\n' "$NVIM_CONFIG"
  printf 'NVIM_DATA=%q\n' "$NVIM_DATA"
  printf 'GITCONFIG=%q\n' "$GITCONFIG"
  printf 'MOUNT_SSH=%s\n' "$MOUNT_SSH"
  printf 'FORWARD_AGENT=%s\n' "$FORWARD_AGENT"
  printf 'CONTAINER_USER=%q\n' "dev"

  sed \
    -e "s|@UID@|$HOST_UID|g" \
    -e "s|@GID@|$HOST_GID|g" \
    -e "s|@NAME@|$NAME|g" \
    -e "s|@DATA_MOUNTED@|$([ -n "$NVIM_DATA" ] && echo 1 || echo 0)|g" \
    <<'STATIC'
set -euo pipefail

run_args=(
  --name "$NAME"
  --label initkit.nvim-workspace=1
  --label "initkit.workspace.dir=$WORKSPACE"
  --user root
  --entrypoint /bin/sh
  --cap-add=SYS_PTRACE
  --security-opt seccomp=unconfined
  --workdir /workspace
  -e "TERM=${TERM:-xterm-256color}"
  -v "$WORKSPACE:/workspace"
)
if [ -n "$NVIM_CONFIG" ]; then
  run_args+=(-v "$NVIM_CONFIG:/home/$CONTAINER_USER/.config/nvim")
fi
if [ -n "$NVIM_DATA" ]; then
  run_args+=(-v "$NVIM_DATA:/home/$CONTAINER_USER/.local/share/nvim")
else
  run_args+=(-v "${NAME}-nvim-data:/home/$CONTAINER_USER/.local/share/nvim")
fi
run_args+=(
  -v "${NAME}-nvim-state:/home/$CONTAINER_USER/.local/state/nvim"
  -v "${NAME}-nvim-cache:/home/$CONTAINER_USER/.cache/nvim"
)
if [ -n "$GITCONFIG" ]; then
  run_args+=(-v "$GITCONFIG:/home/$CONTAINER_USER/.gitconfig")
fi
if [ "$MOUNT_SSH" = 1 ] && [ -d "$HOME/.ssh" ]; then
  run_args+=(-v "$HOME/.ssh:/home/$CONTAINER_USER/.ssh:ro")
fi
if [ "$FORWARD_AGENT" = 1 ] && [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
  run_args+=(-e "SSH_AUTH_SOCK=$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK")
fi
if [ -n "${SHELL_INITS_NO_TMUX:-}" ]; then
  run_args+=(-e "SHELL_INITS_NO_TMUX=$SHELL_INITS_NO_TMUX")
fi
if [ -n "${COLORTERM:-}" ]; then
  run_args+=(-e "COLORTERM=$COLORTERM")
fi

# Container bootstrap: remap the image user to the host uid/gid on first
# start (so mounted files keep their host ownership), then drop into tmux
# (or a login zsh with SHELL_INITS_NO_TMUX=1).
BOOTSTRAP='set -e
trap "exit 0" TERM INT
uid=@UID@
gid=@GID@
user=dev
if [ "$(id -u "$user")" != "$uid" ] || [ "$(id -g "$user")" != "$gid" ]; then
  echo "==> remapping container user to host uid/gid (one-time)"
  if [ "$(id -g "$user")" != "$gid" ] && getent group "$gid" >/dev/null 2>&1; then
    clash=$(getent group "$gid" | cut -d: -f1)
    if [ "$clash" != "$user" ]; then
      groupmod -g $((gid + 60000)) "$clash" 2>/dev/null || groupdel "$clash" 2>/dev/null || true
    fi
  fi
  usermod -u "$uid" "$user" 2>/dev/null || true
  groupmod -g "$gid" "$user" 2>/dev/null || true
  chown -R "$uid:$gid" "/home/$user" 2>/dev/null || true
  if [ "$(id -u "$user")" != "$uid" ] || [ "$(id -g "$user")" != "$gid" ]; then
    echo "initkit: cannot remap user $user to $uid:$gid; rebuild the image with --uid/--gid" >&2
    exit 1
  fi
fi
mkdir -p "/home/$user/.local/state/nvim" "/home/$user/.cache/nvim" 2>/dev/null || true
chown -R "$user" "/home/$user/.local/state/nvim" "/home/$user/.cache/nvim" 2>/dev/null || true
if [ "@DATA_MOUNTED@" != "1" ]; then
  chown -R "$user" "/home/$user/.local/share/nvim" 2>/dev/null || true
fi
# hand the docker client pty to the container user: the container starts as
# root, so the pty stays root-owned and ~/.config/tmux/osc52-copy.sh (nvim and
# tmux y -> OSC 52 to the workstation clipboard) could not write to it
client_tty=$(readlink /proc/self/fd/0 2>/dev/null || true)
case "$client_tty" in
  /dev/pts/*) chown "$uid:$gid" "$client_tty" 2>/dev/null || chmod 666 "$client_tty" 2>/dev/null || true ;;
esac
cd /workspace 2>/dev/null || cd "/home/$user"
if [ "${SHELL_INITS_NO_TMUX:-0}" = "1" ]; then
  exec su "$user" -c "cd \"$PWD\"; exec zsh -l"
fi
echo "==> initkit workspace ready: /workspace (container: @NAME@)"
echo "    shell into it any time: docker exec -it -u $user @NAME@ zsh -l"
while :; do
  su "$user" -c "export SHELL=/usr/bin/zsh; exec tmux new -As main"
  echo
  echo "==> tmux detached; the container keeps running"
  echo "    Enter         -> reattach"
  echo "    Ctrl-p Ctrl-q -> detach for later (rerun this file to return)"
  echo "    Ctrl-d        -> stop the container"
  read -r _discard || exit 0
done'

running=$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)
if [ "$running" = true ]; then
  echo "==> container '$NAME' is running, attaching" >&2
  echo "    (if it waits at the detach hint, press Enter to reattach tmux)" >&2
  exec docker attach "$NAME"
fi
if docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "==> starting existing container '$NAME'" >&2
  if docker start -ai "$NAME"; then
    exit 0
  fi
  echo "[error] docker start failed" >&2
  echo "        with --forward-agent, a moved agent socket (re-login) breaks the mounts:" >&2
  echo "        docker rm '$NAME' and rerun this script to recreate" >&2
  exit 1
fi

echo "==> creating container '$NAME' from '$IMAGE'" >&2
if [ -t 0 ]; then
  exec docker run -it "${run_args[@]}" "$IMAGE" -c "$BOOTSTRAP"
fi
exec docker run -i "${run_args[@]}" "$IMAGE" -c "$BOOTSTRAP"
STATIC
} > "$TARGET"

chmod 0755 "$TARGET"

# --- summary -----------------------------------------------------------------

{
  echo
  echo "==> neovim docker workspace"
  printf '    image:       %s\n' "$IMAGE"
  printf '    container:   %s\n' "$NAME"
  printf '    workspace:   %s -> /workspace\n' "$WORKSPACE"
  if [ -n "$NVIM_CONFIG" ]; then
    printf '    nvim config: %s (host)\n' "$NVIM_CONFIG"
  else
    printf '    nvim config: baked into the image\n'
  fi
  if [ -n "$NVIM_DATA" ]; then
    printf '    plugin data: %s (shared with the host)\n' "$NVIM_DATA"
  else
    printf '    plugin data: per-project container volume\n'
  fi
  if [ -n "$GITCONFIG" ]; then
    printf '    git config:  %s\n' "$GITCONFIG"
  fi
  echo
} >&2

log "wrote $TARGET"
if [ "$RUN" = 1 ]; then
  exec bash "$TARGET"
fi
log "start it with: bash $TARGET"
