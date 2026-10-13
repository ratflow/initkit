# shell-inits

One-command bootstrap of a configured shell environment (tmux + zsh/fzf +
LazyVim/lazygit) on fresh VMs and containers. See [PLAN.md](PLAN.md) for the
full architecture.

## Supported distros

| distro        | status       |
|---------------|--------------|
| ubuntu-26.04  | implemented  |
| ubuntu-24.04  | planned      |
| alpine-3.21   | planned      |

## Usage

On a fresh VM (as a regular user with sudo, or as root):

```sh
curl -fsSL <base-url>/sets/zsh-tmux-neovim.sh | bash -s -- --base-url <base-url>
```

`<base-url>` is the raw-files root of this repository (private git server,
GitHub mirror or any HTTP server serving a checkout). Alternative forms:

```sh
SHELL_INITS_BASE_URL=<base-url> curl -fsSL <base-url>/sets/zsh-tmux-neovim.sh | bash
# or from a checkout:
./sets/zsh-tmux-neovim.sh
```

Individual components can be installed the same way (`core/tmux.sh`,
`core/zsh.sh`, `core/fzf.sh`, `core/lazygit.sh`, `core/neovim.sh`).

### Environment variables

| var                          | effect                                            |
|------------------------------|---------------------------------------------------|
| `SHELL_INITS_BASE_URL`       | base URL of the scripts (raw-files root)          |
| `SHELL_INITS_USER`           | configure this user when running as root (docker) |
| `SHELL_INITS_SKIP`           | comma-separated components to skip (e.g. `tmux`)  |
| `SHELL_INITS_FORCE`          | reinstall even if state markers say "done"        |
| `SHELL_INITS_NVIM_BOOTSTRAP` | `1` = sync nvim plugins headlessly right away     |

## Docker images

Build a fully initialized image (nvim plugins synced at build time, works
offline at runtime) and drop straight into tmux session `main`:

```sh
./dockerfiles/zsh-tmux-neovim.build.sh               # -> shell-inits/zsh-tmux-neovim:ubuntu-26.04
./dockerfiles/zsh-tmux-neovim.build.sh --uid 1001    # bake everything for uid 1001
docker run -it shell-inits/zsh-tmux-neovim:ubuntu-26.04
```

The image is fully initialized at build time (all lazyvim plugins, the
treesitter parser set compiled in, spell files and the tree-sitter CLI), so it
needs no network at runtime. For offline distribution:

```sh
./dockerfiles/zsh-tmux-neovim.build.sh --save         # also writes dist/zsh-tmux-neovim_ubuntu-26.04.tar.gz
docker load -i dist/zsh-tmux-neovim_ubuntu-26.04.tar.gz
```

The build script starts a temporary local HTTP server serving this repository
and builds with `--network=host`, so the image is produced by the exact same
`curl | bash` flow used on VMs. Useful options: `--distro <slug>` (repeatable),
`--all`, `--gid`, `--tag`, `--no-cache`, and `--base-url <url>` for remote
docker hosts or Docker Desktop (where `--network=host` does not work, serve the
repo yourself and pass `http://host.docker.internal:<port>`).

Inside the container: non-root user `dev` with passwordless sudo, entrypoint
runs `tmux new -As main` (set `SHELL_INITS_NO_TMUX=1` for a plain zsh), and
because the user and all files are created with the requested uid/gid, anything
the container writes (mounted volumes included) matches your host user.

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
  scope for now.
- **lazygit**: release binary with matching pastel theme.
