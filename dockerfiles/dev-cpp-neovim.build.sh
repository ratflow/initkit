#!/usr/bin/env bash
# dockerfiles/dev-cpp-neovim.build.sh
# Build fully-initialized initkit/dev-cpp-neovim:<distro> images (C++ dev stack).
#
# Serves this repository over a temporary local HTTP server (so the image build
# uses the exact same curl | bash flow as a VM) and then runs docker build with
# --network=host so the container can reach it.
#
# Usage:
#   ./dockerfiles/dev-cpp-neovim.build.sh [options]
#
# Options:
#   --distro <slug>   repeatable; default: ubuntu-26.04
#   --all             build the whole supported distro matrix
#   --uid <N>         uid of the image user, owns everything (default 1000)
#   --gid <N>         gid of the image user (default: same as --uid)
#   --tag <tag>       image tag (default: distro slug)
#   --no-cache        pass --no-cache to docker build
#   --base-url <url>  fetch scripts from this URL instead of the local server
#                     (useful for remote docker hosts or Docker Desktop:
#                     serve the repo yourself and pass
#                     http://host.docker.internal:<port>)
#   --save            also export the image to dist/<set>_<distro>[_<tag>].tar.gz
#                     for offline use (docker load -i <file>)
#   -h, --help        show this help
#
# Note: --network=host does not exist on Docker Desktop (macOS/Windows);
# there use --base-url with a server reachable from the build container.

set -euo pipefail

SET="dev-cpp-neovim"
SUPPORTED_DISTROS=(ubuntu-26.04)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

DISTROS=()
USER_UID=1000
USER_GID=0
TAG=""
NO_CACHE=0
BASE_URL_OVERRIDE=""
SAVE=0

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | tail -n +2
  exit 0
}

die() { echo "[initkit][error] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case $1 in
    --distro)    DISTROS+=("${2:?--distro needs a value}"); shift 2 ;;
    --all)       DISTROS=("${SUPPORTED_DISTROS[@]}"); shift ;;
    --uid)       USER_UID="${2:?--uid needs a value}"; shift 2 ;;
    --gid)       USER_GID="${2:?--gid needs a value}"; shift 2 ;;
    --tag)       TAG="${2:?--tag needs a value}"; shift 2 ;;
    --no-cache)  NO_CACHE=1; shift ;;
    --base-url)  BASE_URL_OVERRIDE="${2:?--base-url needs a value}"; shift 2 ;;
    --save)      SAVE=1; shift ;;
    -h|--help)   usage ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
done

((${#DISTROS[@]})) || DISTROS=(ubuntu-26.04)
[[ $USER_GID -eq 0 ]] && USER_GID=$USER_UID

command -v docker >/dev/null 2>&1 || die "docker is not available"
command -v python3 >/dev/null 2>&1 || die "python3 is not available"

SRV_PID=""
cleanup() { [[ -n $SRV_PID ]] && kill "$SRV_PID" 2>/dev/null || true; }
trap cleanup EXIT

BASE_URL=$BASE_URL_OVERRIDE
if [[ -z $BASE_URL ]]; then
  PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$REPO_ROOT" >/dev/null 2>&1 &
  SRV_PID=$!
  for _ in $(seq 1 50); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; then
      exec 3>&- 3<&-
      break
    fi
    sleep 0.1
  done
  BASE_URL="http://127.0.0.1:${PORT}"
fi

echo "==> building set '${SET}' (scripts served from: ${BASE_URL})"
for DISTRO in "${DISTROS[@]}"; do
  # distro slug (ubuntu-26.04) -> image reference (ubuntu:26.04)
  DISTRO_REF="${DISTRO/-/:}"
  IMAGE="initkit/${SET}:${TAG:-${DISTRO}}"
  echo "==> image: ${IMAGE} (distro: ${DISTRO_REF}, uid/gid: ${USER_UID}:${USER_GID})"
  # shellcheck disable=SC2086
  docker build \
    ${NO_CACHE:+--no-cache} \
    --network=host \
    --build-arg SHELL_INITS_BASE_URL="${BASE_URL}" \
    --build-arg DISTRO="${DISTRO_REF}" \
    --build-arg USER_UID="${USER_UID}" \
    --build-arg USER_GID="${USER_GID}" \
    -f "${SCRIPT_DIR}/${SET}.dockerfile" \
    -t "${IMAGE}" \
    "${REPO_ROOT}"
  echo "==> built: ${IMAGE}"
  echo "    run:  docker run -it ${IMAGE}"
  if (( SAVE )); then
    _suffix="${DISTRO}"
    [[ -n $TAG ]] && _suffix="${DISTRO}_${TAG}"
    _file="${REPO_ROOT}/dist/${SET}_${_suffix}.tar.gz"
    mkdir -p "${REPO_ROOT}/dist"
    docker save "${IMAGE}" | gzip >"${_file}"
    echo "    saved: ${_file}"
    echo "    load:  docker load -i ${_file}"
  fi
done
echo "==> done"
