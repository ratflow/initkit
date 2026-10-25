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

## Mounting local neovim in docker container

The images above come with the initkit editor config baked in. To work on a
project with **your own** LazyVim setup from the host while using the
container's toolchain (clangd, lldb, gcc, vcpkg, ...), run the workspace tool
in the project directory:

```sh
cd ~/src/git/someproject
curl -fsSL https://raw.githubusercontent.com/ratflow/initkit/master/tools/neovim-docker-workspace.sh | bash
```

It generates `./.nvim-docker-workspace.sh` (self-contained, keep it in the
project) and starts the container:

- the project directory is mounted at `/workspace`,
- your host `~/.config/nvim` is mounted over the container's config - neovim
  inside the container looks and behaves exactly like on the host,
- `~/.local/share/nvim` (plugins, treesitter parsers, mason) is shared as
  well when the host and image neovim versions match; on a version mismatch
  the tool asks and by default keeps a per-project plugin volume instead,
  syncing it once from your `lazy-lock.json` (needs network on first start
  only). Force either mode with `--data` / `--no-data`,
- neovim state/cache (shada, undo history) live in per-project docker
  volumes and survive restarts,
- `~/.gitconfig` is mounted if present; `--ssh` / `--forward-agent` add the
  obvious extras,
- the container user is remapped to your host uid/gid on first start, so
  file ownership is correct in both directions; `SYS_PTRACE` and unconfined
  seccomp are enabled, so lldb/codelldb debugging works,
- clangd, builds and tests see plain `/workspace` paths - nothing to remap
  or configure per side.

### Returning to the project

Re-run the generated script (or the curl one-liner) from the project
directory: it attaches to the container when running, starts it when stopped,
creates it on first use. A tmux detach (`prefix d`) leaves the container
running - press `Enter` to reattach, `Ctrl-d` to stop it. A plain shell any
time: `docker exec -it -u dev <container> zsh -l`. To reset the environment:
`docker rm <container>` and re-run the generator.

### Making a host config container-friendly

Two things commonly need attention in a host LazyVim setup:

**Clipboard.** The container has no X11/Wayland and no clipboard binary
(`xclip`, `wl-copy`, ...) - and installing one inside the container does not
help: clipboard tools talk to an X/Wayland server, which the container does
not have, so they cannot reach your workstation clipboard. The terminal
escape stream is the only channel, so give your config an OSC 52 fallback -
yanks then reach your workstation terminal through the container's tmux
(same mechanism as described in the section above; requires an OSC 52-capable
terminal; VTE-based ones like GNOME Terminal are not):

```lua
-- fall back to OSC 52 when there is no local clipboard tool (containers, ssh).
-- Inside tmux, route through initkit's helper: it writes the escape sequence
-- to the attached client terminals directly, because tmux's own OSC 52
-- forwarding never happens when its client is a docker pty (no real terminal
-- answers tmux's capability queries there).
-- This mirrors config/nvim/lua/config/clipboard.lua from this repository.
local has_clipboard_tool = function()
  local tools = { "xclip", "xsel", "wl-copy", "wl-paste", "pbcopy", "win32yank", "clip.exe" }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool) == 1 then return true end
  end
  return false
end
if not has_clipboard_tool() then
  local osc52 = require("vim.ui.clipboard.osc52")
  local helper = vim.fn.expand("~/.config/tmux/osc52-copy.sh")
  local make_copy
  if vim.env.TMUX and vim.fn.executable(helper) == 1 and vim.system then
    make_copy = function()
      return function(lines, _)
        pcall(function()
          vim.system({ helper }, { stdin = table.concat(lines, "\n") }):wait()
        end)
      end
    end
  else
    make_copy = function(reg) return osc52.copy(reg) end
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = make_copy("+"), ["*"] = make_copy("*") },
    paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
  }
end
```

On the host nothing changes (the real clipboard tool wins); in the container
yanks travel over the terminal escape stream. Restart neovim after adding
the snippet (the provider is chosen once at startup, and only when no
clipboard binary exists - another reason to keep the container clean of
xclip). The workspace tool hands the container's docker pty to the container
user so the helper can write to it (containers created before this fix can
be repaired with `docker exec --user root <container> chown $(id -u):$(id -g)
/dev/pts/0`). Pasting works via the terminal's paste (`Ctrl-Shift-v`) or
tmux (`prefix ]`) - OSC 52 is copy-only in practice.

**neotest-gtest.** The adapter requires each test file (or directory) to be
mapped to a GTest executable once - and the mapping is keyed by absolute
project path (stored under `~/.local/share/nvim/neotest-gtest/`), so the
host and the container keep separate mappings. Inside the container: build
the project, open the neotest summary (`:Neotest summary`), mark the tests
directory with `m`, run `:ConfigureGtest` and point it at the test binary
(e.g. `/workspace/build/debug/mytests`). The mapping persists in the
per-project plugin volume and survives container restarts.

Other notes:

- LSP binaries come from the image's PATH (clangd works out of the box);
  mason-installed binaries from shared host plugin data must be
  self-contained (static) enough for the container's glibc,
- keep host and image neovim versions reasonably close when sharing plugin
  data (treesitter parsers and mason binaries are built for one version), or
  stay in the default `--no-data` mode,
- plugins that store absolute paths (session managers, project markers) see
  `/workspace` inside the container - keep such state per side, like
  neotest-gtest does.

### Options

| option             | effect                                                                |
|--------------------|-----------------------------------------------------------------------|
| `--image <ref>`    | image to use (default `$NVIM_DOCKER_IMAGE` or `initkit/dev-cpp-neovim:ubuntu-26.04`) |
| `--dir <path>`     | project directory to mount as `/workspace` (default `.`)              |
| `--name <name>`    | container name (default `initkit-nvim-<dir>-<hash>`)                  |
| `--data`           | always share the host's `~/.local/share/nvim`                         |
| `--no-data`        | never share it; per-project plugin volume synced from `lazy-lock.json` |
| `--ssh`            | mount `~/.ssh` into the container read-only                           |
| `--forward-agent`  | forward the ssh agent socket (recreate the container after re-login)  |
| `--no-check`       | skip the host-vs-image neovim version and arch checks                 |
| `--no-run`         | only generate the workspace script, do not start it                   |

## Switching to the hybrid/gruvbox theme

Machines provisioned with the default catppuccin look can be switched to the
hybrid setup used on the host with the theme tool:

```sh
curl -fsSL https://raw.githubusercontent.com/ratflow/initkit/master/tools/set-hybrid-theme.sh | bash
```

It comments out the previous `lua/plugins/colorscheme.lua` contents (one-time
`.pre-hybrid` backups, never overwritten) and activates
`chodak166/nvim-hybrid-theme`, then syncs plugins headlessly (lazy.nvim would
also pick the theme up on the next start). It also asks whether to switch the
tmux status theme to `tmux-gruvbox` (dark): the plugin is installed into
`~/.tmux.d/tmux-gruvbox`, the pastel block in `~/.tmux.conf` is commented out
and a running tmux server is reloaded. Re-running is a no-op once the themes
are active; `--no-tmux`, `--no-sync` and custom `--nvim-colorscheme` /
`--tmux-conf` / `--gruvbox-dir` paths are documented in `--help`.

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
