-- initkit: C/C++ language layer for LazyVim (deployed by core/cpp-dev.sh,
-- set: dev-cpp-neovim; the clangd extra itself is imported by config/lazy.lua).
-- clangd / clang-format / clang-tidy are distro packages on PATH, so mason
-- must not download anything: the environment has to keep working fully
-- offline.
return {
  -- use the system clangd directly instead of a mason-managed one
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
        },
      },
    },
  },

  -- format C/C++ with the system clang-format through conform.nvim
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        c = { "clang-format" },
        cpp = { "clang-format" },
      },
    },
  },
}
