# Package name map for ubuntu-26.04 (abstract name -> apt package)
# Used by lib/pkg.sh. Keep abstract names distro-neutral.

declare -gA PKG=(
  [ca-certificates]=ca-certificates
  [curl]=curl
  [wget]=wget
  [git]=git
  [unzip]=unzip
  [tar]=tar

  [tmux]=tmux
  [zsh]=zsh
  [fzf]=fzf
  [neovim]=neovim
  [ripgrep]=ripgrep
  [fd-find]=fd-find
  [gcc]=gcc
  [libc6-dev]=libc6-dev
)
