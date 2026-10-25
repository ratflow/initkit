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
  [g++]=g++
  [libc6-dev]=libc6-dev
  [make]=make
  [cmake]=cmake
  [ninja]=ninja-build
  [clangd]=clangd
  [clang-format]=clang-format
  [clang-tidy]=clang-tidy
  [lldb]=lldb
  [bear]=bear
  [pkg-config]=pkg-config
  [zip]=zip
  [unzip]=unzip
)
