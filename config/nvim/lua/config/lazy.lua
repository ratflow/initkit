-- initkit: lazy.nvim bootstrap + LazyVim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- spec order matters for LazyVim's import check: lazyvim.plugins, then the
-- lazyvim extras, then our own plugins. The C++ extras are only imported when
-- the cpp layer is deployed (core/cpp-dev.sh, sets/dev-cpp-neovim); the
-- cpp-*.lua spec files are the sentinel.
local spec = {
  { "LazyVim/LazyVim", import = "lazyvim.plugins" },
}
if (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("config") .. "/lua/plugins/cpp-clangd.lua") then
  vim.list_extend(spec, {
    { import = "lazyvim.plugins.extras.lang.clangd" },
    { import = "lazyvim.plugins.extras.dap.core" },
    { import = "lazyvim.plugins.extras.test.core" },
  })
end
table.insert(spec, { import = "plugins" })

require("lazy").setup({
  spec = spec,
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "catppuccin", "habamax" } },
  checker = {
    enabled = true,
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
