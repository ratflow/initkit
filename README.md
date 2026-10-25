# initkit

One-command bootstrap of a configured shell environment.

Available sets:

 - base: zsh + fzf + tmux
 - neovim: base set + LazyVim + lazygit
 - cpp: neovim + basic C++ toolchain.

Works on fresh VMs and as pre-baked, offline-ready Docker images.

## Quick start

### On a fresh VM

As a regular user with sudo (or as root), one command sets everything up:

```sh
# zsh + fzf + tmux (shell only, no editors)
curl -fsSL https://v.gd/initkit_zt | bash
```

```sh
# the base set + LazyVim + lazygit
curl -fsSL https://v.gd/initkit_ztn | bash
```

```sh
# the same, plus the C++ stack: cmake, vcpkg, clangd, bear, lldb/codelldb,
# LazyVim debugger (nvim-dap) and test runner (neotest + GoogleTest)
curl -fsSL https://v.gd/initkit_ztnc | bash
```

When it finishes, open a new login shell (or `exec zsh`) and run:

```sh
tmux new -As main
```

Everything is idempotent: re-running a set only fills the gaps. Use
`SHELL_INITS_FORCE=1` to reinstall, `SHELL_INITS_SKIP=tmux,neovim` to exclude
components (see [Environment variables](#environment-variables)).

### With Docker

Build a fully initialized image (configs, all nvim plugins, compiled
treesitter parsers and - for C++ - the vcpkg cache are baked in at build time,
so the image needs no network at runtime):

```sh
./dockerfiles/zsh-tmux-neovim.build.sh    # -> initkit/zsh-tmux-neovim:ubuntu-26.04
./dockerfiles/dev-cpp-neovim.build.sh     # -> initkit/dev-cpp-neovim:ubuntu-26.04
```

Run it - you land in tmux session `main` as user `dev` (passwordless sudo,
uid/gid matching your host if built with `--uid`/`--gid`):

```sh
docker run -it initkit/zsh-tmux-neovim:ubuntu-26.04
docker run -it initkit/dev-cpp-neovim:ubuntu-26.04
```

For offline environments, export the image and load it on the target machine:

```sh
./dockerfiles/dev-cpp-neovim.build.sh --save
docker load -i dist/dev-cpp-neovim_ubuntu-26.04.tar.gz
```

## Sets

| set               | contents                                                        |
|-------------------|-----------------------------------------------------------------|
| `zsh-tmux`        | zsh + fzf, tmux (no prebuilt docker image; the curl flow above installs it in seconds) |
| `zsh-tmux-neovim` | the above + LazyVim, lazygit                                    |
| `dev-cpp-neovim`  | the above + cmake/ninja/gcc/g++, vcpkg, clangd, bear, lldb + codelldb, nvim-dap, neotest/GoogleTest, `~/cpp-sample` demo project |

Individual components can be installed the same way, one tool at a time:
`core/tmux.sh`, `core/zsh.sh`, `core/fzf.sh`, `core/lazygit.sh`,
`core/neovim.sh`, `core/cpp-dev.sh`.

### What the C++ set gives you

- **build**: cmake, ninja, gcc/g++ (GCC 15 on ubuntu-26.04), make, pkg-config
- **dependencies**: [vcpkg](https://github.com/microsoft/vcpkg) at `/opt/vcpkg`
  (pinned release tag, see `versions.env`), user-owned, `VCPKG_ROOT` set and
  `vcpkg` on PATH in zsh
- **code intelligence**: clangd, clang-format, clang-tidy
- **compile_commands for non-cmake projects**: `bear -- make`
- **debugging**: codelldb (nvim-dap adapter) with its bundled lldb (CLI +
  liblldb), installed self-contained under `/usr/local/lib/codelldb`
- **tests**: neotest with the GoogleTest adapter
- **`~/cpp-sample`**: a minimal cmake + vcpkg + gtest project demonstrating
  the whole loop - build it, run it, run its tests, set a breakpoint and debug
  it (pre-built in the docker image, rebuildable offline):

  ```sh
  cd ~/cpp-sample
  cmake --preset debug && cmake --build --preset debug
  ./build/debug/cpp-sample
  ctest --preset debug
  ```

  In nvim: `<leader>db` breakpoint, `<leader>dc` run/continue, `<leader>tr`
  run nearest test, `<leader>td` debug nearest test, `gd`/`gr`/`K` code
  navigation.

## Supported distros

| distro        | status       |
|---------------|--------------|
| ubuntu-26.04  | implemented  |
| ubuntu-24.04  | planned      |
| alpine-3.21   | planned      |

## Alternative ways to install

The quick start fetches scripts from this repository's `master` branch. You
can point the tools at any other checkout or HTTP server instead:

```sh
# from a local checkout
./sets/zsh-tmux.sh
./sets/dev-cpp-neovim.sh

# from another branch/server
curl -fsSL <base-url>/sets/dev-cpp-neovim.sh | bash -s -- --base-url <base-url>
# or
SHELL_INITS_BASE_URL=<base-url> curl -fsSL <base-url>/sets/dev-cpp-neovim.sh | bash
```

`<base-url>` is the raw-files root of the scripts (e.g.
`https://raw.githubusercontent.com/ratflow/initkit/master`).

### Environment variables

| var                          | effect                                            |
|------------------------------|---------------------------------------------------|
| `SHELL_INITS_BASE_URL`       | base URL of the scripts (raw-files root)          |
| `SHELL_INITS_USER`           | configure this user when running as root (docker) |
| `SHELL_INITS_SKIP`           | comma-separated components to skip (e.g. `tmux`)  |
| `SHELL_INITS_FORCE`          | reinstall even if state markers say "done"        |
| `SHELL_INITS_NVIM_BOOTSTRAP` | `1` = sync/verify nvim plugins and build the sample project headlessly (used by image builds; failures become fatal) |

## Docker images in detail

- base image: plain distro (`ubuntu:26.04`), nothing preinstalled beyond a
  downloader; everything above comes from the set scripts,
- build process: the build script serves this repository over a temporary
  local HTTP server and runs `docker build --network=host`, so images are
  produced by the exact same `curl | bash` flow used on VMs,
- useful options: `--distro <slug>` (repeatable), `--all`, `--uid`, `--gid`,
  `--tag`, `--no-cache`, `--save`, and `--base-url <url>` for remote docker
  hosts or Docker Desktop (where `--network=host` does not work, serve the
  repo yourself and pass `http://host.docker.internal:<port>`),
- inside the container: non-root user `dev` with passwordless sudo, the
  entrypoint runs `tmux new -As main` (set `SHELL_INITS_NO_TMUX=1` for a plain
  zsh), and because the user and all files are created with the requested
  uid/gid, anything the container writes (mounted volumes included) matches
  your host user.

### Clipboard sharing (no X11/Wayland needed)

Copy/paste between the container/VM and your workstation uses the OSC 52
terminal escape sequence, which travels through the same byte stream as the
terminal display - it works over ssh, `docker run -it` and inside tmux without
mounting any sockets. Requirements:

- your terminal must support OSC 52 (kitty, wezterm, iTerm2, alacritty,
  windows terminal do; kitty has it enabled by default),
- tmux runs with a UTF-8 locale (set automatically; an already-running tmux
  server keeps its original environment - restart it after upgrading).

How it works:

- tmux copy mode: `y` copies into the tmux buffer (paste with `prefix ]`) and
  writes the selection to your workstation clipboard via
  `~/.config/tmux/osc52-copy.sh`, which talks to the client terminals directly,
- nvim: yanks go to the `+` register through neovim's built-in OSC 52 provider
  (activated whenever no local clipboard tool exists); tmux forwards it.

## What you get

- **zsh**: two-line pastel prompt (`login@host ../end/of/path <branch>`), git
  info cached per command (refreshed only after commands or directory changes)
  and kept fast in huge repos via `core.untrackedCache` + `core.fsmonitor`,
  autosuggestions, syntax highlighting, fzf bindings - no plugin manager, no
  nerd fonts required.
- **tmux**: vi copy mode, clipboard shared with your workstation over ssh via
  OSC 52, pastel (catppuccin macchiato) status theme, no plugins.
- **LazyVim**: catppuccin theme, snacks explorer tweaks, OSC52 clipboard over
  ssh, 42 treesitter parsers + spell files precompiled during image builds
  (works fully offline). Language-specific plugins are intentionally out of
  scope for the base set - see the `dev-cpp-neovim` set for the C++ layer.
- **lazygit**: release binary with matching pastel theme.

## How it works

Three small layers keep the project easy to extend:

- `core/*.sh` - one atomic, idempotent initializer per tool (distro
  differences isolated in `lib/pkgmaps/`), runnable standalone,
- `sets/*.sh` - curl-able compositions of core initializers (the "sets"),
- `dockerfiles/*` - image targets that run a set inside `docker build` and
  finish the offline provisioning (plugin sync, sample build).
