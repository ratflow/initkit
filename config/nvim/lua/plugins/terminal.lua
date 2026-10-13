-- shell-inits: terminal UX layered on snacks (<leader>tt, <leader>ft, <C-/>)
return {
  "chodak166/snacks-terminal-ctl.nvim",
  name = "snacks-terminal-ctl.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "VeryLazy",
  opts = {},
}
