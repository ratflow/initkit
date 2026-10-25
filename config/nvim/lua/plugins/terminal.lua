-- initkit: terminal UX layered on snacks (<leader>ft, <C-/> and
-- 99<C-/> for the floating terminal). <leader>tt is intentionally unbound:
-- in the dev-cpp-neovim set it is LazyVim's neotest "run file" key.
return {
  "chodak166/snacks-terminal-ctl.nvim",
  name = "snacks-terminal-ctl.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "VeryLazy",
  opts = {
    keys = {
      float = false,
    },
  },
}
