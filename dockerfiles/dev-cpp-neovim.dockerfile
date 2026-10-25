# dockerfiles/dev-cpp-neovim.dockerfile
# Fully initialized C++ development image: the zsh-tmux-neovim toolset plus
# cmake/gcc/ninja, vcpkg, clangd, bear, lldb/codelldb, lazyvim clangd+dap+
# neotest layers and a pre-built sample project. Ready to use offline: all
# nvim plugins are synced and the vcpkg binary cache is prewarmed at build
# time by core/cpp-dev.sh (SHELL_INITS_NVIM_BOOTSTRAP=1).
# Built by dockerfiles/dev-cpp-neovim.build.sh, which serves this repository
# over a local HTTP server and passes SHELL_INITS_BASE_URL.

# DISTRO is a docker image reference (build.sh maps the distro slug, e.g.
# ubuntu-26.04, to ubuntu:26.04)
ARG DISTRO=ubuntu:26.04
FROM ${DISTRO}

ARG SHELL_INITS_BASE_URL
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# downloader + git (vcpkg clone) + sudo for the dev user
RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    curl ca-certificates git sudo \
  && rm -rf /var/lib/apt/lists/*

# non-root user with the requested uid/gid; evict a colliding stock user
# (ubuntu:26.04 ships an 'ubuntu' user at 1000:1000) and make sure every file
# produced from here on is owned by the requested uid
RUN set -eu; \
  if getent passwd "${USER_UID}" >/dev/null; then \
  userdel -r "$(getent passwd "${USER_UID}" | cut -d: -f1)" || true; fi; \
  if getent group "${USER_GID}" >/dev/null; then \
  groupdel "$(getent group "${USER_GID}" | cut -d: -f1)" || true; fi; \
  groupadd -g "${USER_GID}" "${USERNAME}" \
  && useradd -m -s /bin/bash -u "${USER_UID}" -g "${USER_GID}" "${USERNAME}" \
  && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
  && chmod 440 "/etc/sudoers.d/${USERNAME}"

# run the toolset as root, provisioning the user's environment;
# SHELL_INITS_NVIM_BOOTSTRAP=1 puts core/neovim.sh + core/cpp-dev.sh into
# strict image-build mode: lazyvim plugins synced, cpp layer verified, sample
# project built + tested and the vcpkg binary cache prewarmed
RUN curl -fsSL "${SHELL_INITS_BASE_URL}/sets/dev-cpp-neovim.sh" \
  | env SHELL_INITS_BASE_URL="${SHELL_INITS_BASE_URL}" \
        SHELL_INITS_USER="${USERNAME}" \
        SHELL_INITS_NVIM_BOOTSTRAP=1 \
        bash

# slim down (vcpkg buildtrees/downloads caches are kept on purpose: they make
# offline rebuilds of the same dependency set possible)
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# vcpkg on PATH for every process (shells also get it via ~/.zshenv)
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH="/opt/vcpkg:${PATH}"

COPY dockerfiles/entrypoint.sh /usr/local/bin/shell-inits-entrypoint
RUN chmod 0755 /usr/local/bin/shell-inits-entrypoint

USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENV SHELL=/usr/bin/zsh
# UTF-8 locale for the tmux server and everything else in the container
ENV LANG=C.UTF-8
ENTRYPOINT ["/usr/local/bin/shell-inits-entrypoint"]
