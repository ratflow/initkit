-- shell-inits: catppuccin (macchiato) as the default colorscheme
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "macchiato",
      integrations = {
        cmp = true,
        gitsigns = true,
        treesitter = true,
        notify = true,
        mini = true,
        snacks = true,
        telescope = { enabled = true },
        which_key = true,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
