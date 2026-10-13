# shell-inits - Repository Plan

One-command bootstrap of fully configured shell environments on fresh VMs and in
Docker containers, plus pre-baked Docker images.

```
# on any fresh VM (ubuntu 24.04/26.04, alpine 3.21):
curl -fsSL https://git.example.com/shell-inits/raw/main/sets/zsh-tmux-neovim.sh | bash

# pre-baked image:
./dockerfiles/zsh-tmux-neovim.build.sh                     # -> local image
docker run -it shell-inits/zsh-tmux-neovim:ubuntu-24.04    # lands in tmux session 'main'
```

## 1. Goals

1. Single command to get a working, configured environment on a new VM or in a
   running container (tmux, zsh+fzf, lazyvim+lazygit, custom yazi build, ...).
2. Distro-agnostic entry points: same URL works on `ubuntu:24.04`,
   `ubuntu:26.04`, `alpine:3.21` (auto-detected).
3. Layered composition: atomic core initializers, combined into toolsets,
   reusable in Dockerfiles.
4. Pre-built, fully initialized Docker images (nvim plugins already synced,
   tmux plugins installed) that need no network at runtime. A private Docker
   registry will distribute them in the future; until then `build.sh` only
   builds locally.
5. Source portability: scripts/configs can be served from GitHub, a private git
   server, or a company internal HTTP server without changing any code.
6. Trivially extensible: adding a new tool, a new toolset, or a new distro
   should each be a small, localized addition.

Non-goals (for now): managing dotfiles unrelated to these tools, secret
management, multi-user provisioning, X/GUI tooling.

## 2. Design principles

- **Layered**: core (one tool) -> set (composition) -> image (docker). Each
  layer only knows the one below it through stable contracts.
- **Idempotent**: every script can be re-run safely; already-satisfied steps
  are skipped based on state markers.
- **Same URL everywhere**: distro differences never leak into entry points;
  they live in `lib/distro.sh` + `lib/pkgmaps/`.
- **Everything is a parameter**: base URL, uid, force/unattended flags are env
  vars/flags with sane defaults; nothing is hardcoded to one host.
- **Plain shell only**: bash + curl/wget. No build step, no dependencies beyond
  what the target distro provides or the scripts themselves install.
- **Simple over featureful**: no zsh plugin manager, no elaborate framework.
  These environments exist to get jobs done on remote servers - well-configured
  and nice looking, with minimal moving parts.
- **Fail loudly and early**: `set -euo pipefail` everywhere, unsupported distros
  abort with a clear message listing supported ones.

## 3. Architecture

```
                     +--------------------------------------------+
                     |  lib/  (shared runtime, fetched on demand)  |
                     |  common, distro, pkg, fetch, asset, state   |
                     +----------------------+---------------------+
                                            |
   Layer 1: core/                  Layer 2: sets/              Layer 3: dockerfiles/
   one tool per script             ordered composition        <name>.dockerfile
   tmux, zsh, fzf, neovim,   -->   zsh-fzf, zsh-tmux,   -->    <name>.build.sh
   lazygit, yazi ...               zsh-tmux-neovim ...         (http server + build)
```

- `core/*.sh` can be run standalone (`curl BASE/core/tmux.sh | bash`) or as
  building blocks.
- `sets/*.sh` are thin, self-bootstrapping wrappers that declare an ordered
  component list and delegate to a shared runner in `lib/`. Curl-able directly,
  so each toolset keeps a stable URL.
- `dockerfiles/*` build images by running one set script inside the build, then
  executing headless bootstraps (nvim `Lazy! sync`, tmux plugin install, ...) so
  images work fully offline at runtime.

## 4. Directory tree

```
shell-inits/
├── README.md                      # usage, quickstart, supported matrix
├── PLAN.md                        # this document
├── Makefile                       # convenience: serve, build SET=.. DISTRO=.., test
├── versions.env                   # versions of tools fetched as release binaries
│                                  #   (only where pinning is free; see 8.4)
│
├── lib/                           # shared shell library (sourced by every script)
│   ├── common.sh                  # strict mode, logging (log/warn/die), arg parsing,
│   │                              #   sudo/root abstraction (as_root), HOME resolution
│   │                              #   (honors SUDO_USER), BASE_URL resolution
│   ├── distro.sh                  # /etc/os-release -> DISTRO_SLUG (ubuntu-24.04,
│   │                              #   ubuntu-26.04, alpine-3.21); unsupported -> abort
│   ├── pkg.sh                     # pkg_update / pkg_install dispatching to apt|apk
│   ├── pkgmaps/                   # per-distro package name tables (abstract -> real)
│   │   ├── ubuntu-24.04.sh
│   │   ├── ubuntu-26.04.sh
│   │   └── alpine-3.21.sh
│   ├── fetch.sh                   # fetch <relpath> [dest]: curl|wget fallback,
│   │                              #   local-checkout mode, optional checksum verify
│   ├── asset.sh                   # install GitHub release binaries, arch-aware
│   │                              #   (x86_64/aarch64), musl vs glibc asset selection
│   ├── state.sh                   # idempotency: mark/query component versions in
│   │                              #   ~/.local/state/shell-inits/
│   └── run-set.sh                 # shared set runner (executes COMPONENTS in order,
│                                  #   applies post hooks, prints summary)
│
├── core/                          # LAYER 1: one atomic initializer per tool
│   ├── tmux.sh                    # tmux + config (plugin-free pastel theme,
│   │                              #   vi copy mode, OSC52 clipboard over ssh)
│   ├── zsh.sh                     # zsh + config + vendored plugins via plain
│   │                              #   git clones, no plugin manager
│                                  #   (autosuggestions, syntax-highlighting)
│   │                              #   prompt: cached git info, big-repo safe
│   ├── fzf.sh                     # fzf (distro pkg or release binary)
│   ├── neovim.sh                  # nvim + lazyvim starter + personal config layer
│   ├── lazygit.sh                 # lazygit binary + config
│   └── yazi.sh                    # custom yazi build: prebuilt release by default,
│                                  #   SHELL_INITS_BUILD_FROM_SOURCE=1 -> cargo build
│
├── sets/                          # LAYER 2: toolsets (stable curl-able entry points)
│   ├── zsh-fzf.sh
│   ├── zsh-tmux.sh
│   ├── zsh-tmux-neovim.sh         # + lazyvim + lazygit
│   └── zsh-tmux-neovim-yazi.sh    # the "everything" example
│
├── config/                        # config payloads installed by core scripts
│   │                              #   (single source of truth: this repo)
│   ├── tmux/                      # tmux.conf, tpm plugin list
│   ├── zsh/                       # .zshrc, .zshenv, prompt, plugin list
│   ├── nvim/                      # lazyvim starter + lua/ personal layer
│   ├── lazygit/                   # config.yml
│   └── yazi/                      # yazi.toml, keymap.toml, theme.toml
│
├── dockerfiles/                   # LAYER 3: image targets (set <-> dockerfile 1:1)
│   ├── _template.dockerfile       # copy & edit to add a new image target
│   ├── _template.build.sh
│   ├── entrypoint.sh              # shared entrypoint: exec tmux new -As main
│   ├── zsh-tmux.dockerfile
│   ├── zsh-tmux.build.sh
│   ├── zsh-tmux-neovim.dockerfile
│   ├── zsh-tmux-neovim.build.sh
│   └── ...
│
└── tests/                         # see section 10 for the strategy
    ├── run.sh                     # builds target image(s) + runs asserts, distro matrix
    ├── core/                      # one dockerfile+test per core initializer
    │   ├── tmux.dockerfile        #   minimal image: distro + ONE core initializer
    │   ├── tmux.test.sh           #   asserts only that tool's outcomes
    │   ├── zsh.dockerfile / zsh.test.sh
    │   ├── fzf.dockerfile / fzf.test.sh
    │   ├── neovim.dockerfile / neovim.test.sh
    │   ├── lazygit.dockerfile / lazygit.test.sh
    │   └── yazi.dockerfile / yazi.test.sh
    └── sets/                      # ONLY sets with steps beyond the sum of cores
        ├── zsh-tmux-neovim.dockerfile
        └── zsh-tmux-neovim.test.sh  # asserts only set extras (plugin sync, session boot)
```

## 5. Layer 1: core initializers (contract)

Every `core/<tool>.sh`:

1. Starts with the standard preamble (see 8.1): resolves BASE_URL, ensures a
   downloader exists, fetches and sources `lib/common.sh`, `lib/distro.sh`,
   `lib/pkg.sh`, `lib/fetch.sh`, `lib/state.sh`.
2. Declares its contract in a header comment: what it installs, env vars it
   honors, which distros need special handling.
3. Is idempotent: checks state markers first, skips if satisfied unless
   `SHELL_INITS_FORCE=1`.
4. Declares dependencies via `ensure_core <other>` (e.g. `zsh.sh` ensures
   `fzf.sh`; `neovim.sh` ensures `lazygit.sh` as a lazyvim dependency) so
   standalone execution always converges.
5. Installs distro-specific bits behind `case "$DISTRO_SLUG"` guards:
   - `fzf`: apt/apk package where new enough, otherwise release binary.
   - `neovim`: release binary or distro package.
   - `yazi`: release binary (musl/glibc asset per distro, arch-aware) or
     optional from-source cargo build.
6. Deploys config from `${BASE_URL}/config/<tool>/` (configs live in this repo,
   no external dotfiles source) into the target user's home, never root's home
   when invoked with sudo.
7. Ends with `state_mark <tool> <version>` and a one-line summary.

## 6. Layer 2: sets / toolsets

`sets/<name>.sh` is a thin curl-able wrapper with the same preamble, then:

```sh
SET_NAME="zsh-tmux-neovim"
COMPONENTS=(fzf zsh tmux lazygit neovim)   # order matters
# optional: SET_POSTHOOKS=(set_default_shell print_next_steps)
source_run_set   # fetches lib/run-set.sh and executes COMPONENTS
```

- The runner reuses core state markers, so sets over already-partially
  provisioned machines only fill gaps.
- Post hooks handle cross-cutting finishers: `chsh -s zsh`, shell-completion
  warmup, motd/summary with next steps.
- Naming convention: components joined with `-` (`zsh-tmux-neovim`). The set
  name doubles as the docker image target name in `dockerfiles/`.

## 7. Layer 3: docker images

Every image target is a pair (exact naming as requested):

- `dockerfiles/<set>.dockerfile`
- `dockerfiles/<set>.build.sh`

### 7.1 Dockerfile sketch (template)

```dockerfile
ARG DISTRO=ubuntu-24.04
FROM ${DISTRO}                       # ubuntu:24.04 | ubuntu:26.04 | alpine:3.21
ARG SHELL_INITS_BASE_URL
ARG USERNAME=dev                     # non-root user, never root-only images
ARG USER_UID=1000                    # owner of everything the build produces
ARG USER_GID=1000                    # override for company setups (1001, ...)
# 1. downloader + ca-certificates (apt or apk depending on DISTRO)
# 2. create group/user with USER_UID:USER_GID + sudo/doas equivalent
# 3. RUN curl -fsSL ${SHELL_INITS_BASE_URL}/sets/<set>.sh | \
#        SHELL_INITS_BASE_URL=${SHELL_INITS_BASE_URL} bash   (as USERNAME)
# 4. headless bootstraps (as USERNAME) so the image is fully initialized:
#      nvim --headless "+Lazy! sync" +qa
#      tmux new-session -d '~/.tmux/plugins/tpm/bin/install_plugins' || true
#      yazi --version; lazygit --version   # warm first-run dirs
# 5. cleanup package caches to slim the image
COPY dockerfiles/entrypoint.sh /usr/local/bin/shell-inits-entrypoint
USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENTRYPOINT ["/usr/local/bin/shell-inits-entrypoint"]   # exec tmux new -As main
```

The UID contract: because the user and every file in its home are created with
`USER_UID`/`USER_GID` at build time, anything the container later produces
(volumes, mounted workspaces, files shared with the host) is owned by the uid
the image was built for.

### 7.2 build.sh responsibilities

1. Resolve repo root; refuse to run outside a checkout.
2. Start a local HTTP server on a free port serving the repo root
   (`python3 -m http.server <port>`), `trap` cleanup.
3. `docker build --network=host
   --build-arg SHELL_INITS_BASE_URL=http://127.0.0.1:<port>
   --build-arg USER_UID=<uid> --build-arg USER_GID=<gid>
   --build-arg DISTRO=<arg or matrix>` (host networking avoids
   `host.docker.internal` issues on Linux; documented fallback for
   Docker Desktop).
4. `--uid N` flag (default 1000) so images can be baked for the user's real uid;
   `--distro` repeatable, `--all` for the whole matrix.
5. Done: image is tagged locally as `shell-inits/<set>:<distro-slug>`. Print the
   exact `docker run` command. No export step - a private registry will be added
   later and publishing becomes a `--push` flag (naming is already
   registry-ready).

## 8. Cross-cutting mechanics

### 8.1 Base URL resolution (portability core)

Resolution order, evaluated in every entry script:

1. `--base-url <url>` CLI arg (passed via `bash -s -- ...` when piped),
2. `SHELL_INITS_BASE_URL` env,
3. local-checkout autodetect: if the running script exists on disk, use repo
   root directly (`fetch` then reads files instead of HTTP). This makes
   `./sets/zsh-tmux.sh` work for development and inside `COPY`-based builds
   without a server.
4. embedded `DEFAULT_BASE_URL` constant (set once per deployment of this repo;
   points at the private git server raw endpoint by default).

`lib/fetch.sh` normalizes the difference between "raw file root" URL shapes
(github raw, gitea/gitlab `raw/main`, plain http dir) with a small
`raw_url <base> <path>` helper; base is always stored as the raw root. Configs
are always fetched relative to BASE_URL from this repo's `config/`.

### 8.2 Distro detection and package abstraction

- `lib/distro.sh` parses `/etc/os-release` -> `DISTRO_SLUG`:
  `ubuntu-24.04`, `ubuntu-26.04`, `alpine-3.21`. Unknown -> hard error listing
  supported slugs and where to add a new `lib/pkgmaps/<slug>.sh`.
- `pkg_install <abstract...>` looks up `lib/pkgmaps/${DISTRO_SLUG}.sh`
  (associative `PKG[abstract]=real-package`) and calls apt/apk. When a package
  is missing or too old, core scripts fall back to `asset_install_github`
  from `lib/asset.sh`.
- Alpine specifics handled in one place: musl asset selection, busybox wget
  quirks, root-by-default (no sudo), openrc absence.

### 8.3 Root vs user

- Containers: run as root, config goes to the created user's home (with the
  requested `USER_UID`/`USER_GID`).
- VMs: run as regular user; privileged ops go through `as_root` (sudo on
  ubuntu, doas/su on alpine), config always lands in the invoking user's home
  (via `SUDO_USER`), default shell switched for that user only.

### 8.4 State, idempotency, versions

- Markers: `~/.local/state/shell-inits/<tool>.ver` (content = installed
  version) for user-scope, `/var/lib/shell-inits/` for system-scope.
- `SHELL_INITS_FORCE=1` reinstalls; `SHELL_INITS_SKIP` list excludes
  components from a set run.
- Pinning is kept only where it costs nothing: `versions.env` pins just the
  GitHub-release binaries that `asset.sh` downloads (where the version is a
  natural part of the URL anyway). apt/apk packages are used as-is from the
  distro - pinning those would add maintenance overhead for no real benefit.

### 8.5 Logging and robustness

- Uniform prefix `[[set|tool] distro]` per line; `SHELL_INITS_LOG` writes a
  full transcript next to state markers.
- Unattended mode (`SHELL_INITS_UNATTENDED=1`, default inside docker builds)
  suppresses prompts; interactive confirmations only for destructive steps.

## 9. End-to-end flows

### 9.1 Fresh VM (online)

```
curl -fsSL $BASE/sets/zsh-tmux-neovim.sh | bash -s -- --base-url $BASE
  -> preamble resolves BASE_URL, ensures downloader, sources lib
  -> distro detect (e.g. ubuntu-26.04)
  -> for c in fzf zsh tmux lazygit neovim: fetch+run core/$c.sh (idempotent)
  -> post hooks: chsh, summary + next steps
```

No args needed when the embedded DEFAULT_BASE_URL is correct; `--base-url` (or
env) covers company-internal mirrors without any code change.

### 9.2 Inside a running container (online)

Same command as 9.1; scripts detect root, skip sudo, install into root or
`SHELL_INITS_USER` if provided.

### 9.3 Building images

```
./dockerfiles/zsh-tmux-neovim.build.sh --distro ubuntu-24.04 --distro alpine-3.21 --uid 1001
  -> local http.server serves repo (trap cleanup)
  -> docker build --network=host (set script + headless bootstraps inside,
     everything owned by uid 1001)
  -> tagged shell-inits/zsh-tmux-neovim:ubuntu-24.04 etc., run command printed
```

### 9.4 Running pre-built images

```
docker run -it shell-inits/zsh-tmux-neovim:ubuntu-24.04
  -> entrypoint execs: tmux new -As main   (attaches to or creates session 'main')
```

Plugins, configs, binaries: all already baked in; no network needed at runtime.
Until the registry exists, ad-hoc offline transfer with a manual `docker save`
is still possible - it is just not build.sh's job.

### 9.5 Development / testing loop

```
./sets/zsh-tmux.sh                 # local mode, no HTTP server needed
make test-core TOOL=tmux           # core assert for every distro
make test-set SET=zsh-tmux-neovim  # set-specific extras only
```

## 10. Testing strategy

Principle: **test each behavior exactly once, at the lowest layer that owns
it.** Overlapping set tests would re-verify what core tests already cover.

- **Core tests (always, full distro matrix)**: `tests/core/<tool>.dockerfile`
  builds a minimal image (base distro + that single core initializer, served
  via the same local-http flow). `tests/core/<tool>.test.sh` asserts only that
  tool's outcomes: binary present and runs (`tmux -V`, `zsh -c true`,
  `nvim --headless +qa`, `lazygit --version`, `yazi --version`), config files
  deployed into the right home, and correct file ownership.
- **Set tests (only sets with steps beyond the sum of their cores)**:
  currently just `zsh-tmux-neovim`, because of the headless plugin
  initialization. Its test asserts only the extras: lazyvim plugins exist under
  `~/.local/share/nvim`, nvim starts clean headlessly, tmux session named
  `main` boots via the entrypoint. It never re-checks tmux/zsh/fzf basics - if
  those broke, the corresponding core test fails first.
- **Sets without extra steps** (e.g. `zsh-fzf`, `zsh-tmux`) get no image and no
  test of their own; their correctness is composition, already implied by core
  tests, and they remain curl-able for interactive use.
- Runner: `tests/run.sh <core|set>/<name> [--distro ...]` orchestrates build +
  assert + cleanup for the whole matrix; Makefile wraps the common cases.

## 11. Extensibility recipes

- **New core initializer**: add `core/<tool>.sh` following the contract (5),
  optionally `config/<tool>/`, pkgmap entries, a line in `versions.env` if it
  uses release binaries, and `tests/core/<tool>.{dockerfile,test.sh}`.
  Immediately usable standalone and from any set.
- **New toolset**: add `sets/<name>.sh` wrapper listing `COMPONENTS`; stable
  URL appears automatically. Add a dockerfile pair / tests only if the set
  performs extra initialization steps.
- **New image target**: copy `dockerfiles/_template.*` to `<set>.*`.
- **New distro**: add `lib/pkgmaps/<slug>.sh`, extend `lib/distro.sh` allow
  list, add alpine-style special cases only where truly needed.

## 12. Naming conventions summary

| Thing             | Pattern                                   | Example                          |
|-------------------|-------------------------------------------|----------------------------------|
| distro slug       | `<id>-<version>`                          | `ubuntu-24.04`, `alpine-3.21`    |
| core script       | `core/<tool>.sh`                          | `core/lazygit.sh`                |
| core test         | `tests/core/<tool>.{dockerfile,test.sh}`  | `tests/core/yazi.test.sh`        |
| set script        | `sets/<components-joined>.sh`             | `sets/zsh-tmux-neovim.sh`        |
| set test          | `tests/sets/<set>.{dockerfile,test.sh}`   | only for sets with extra steps   |
| dockerfile pair   | `dockerfiles/<set>.{dockerfile,build.sh}` | `dockerfiles/zsh-tmux.build.sh`  |
| image             | `shell-inits/<set>:<distro-slug>`         | `shell-inits/dev:alpine-3.21`    |
| env prefix        | `SHELL_INITS_*`                           | `SHELL_INITS_BASE_URL`           |

## 13. Future work

- Private Docker registry: `build.sh --push` once the registry exists; image
  naming (12) is already registry-ready.
- Async prompt git info (zle -F / zpty worker) instead of the current cached
  synchronous approach; big-repo performance is already covered by
  core.untrackedCache + core.fsmonitor.
- Multi-arch image builds (x86_64 + aarch64) if arm hosts or apple silicon
  docker desktops become a target.
