-- shell-inits: options on top of LazyVim defaults

-- sync clipboard with the + register by default (OSC52 over ssh, see clipboard.lua)
vim.opt.clipboard = "unnamedplus"

-- spellcheck: polish + english, change runtime by :opt.spelllang = { "en_gb" }
vim.opt.spelllang = { "pl", "en" }

-- do not hide markup (**, ``` etc)
vim.opt.conceallevel = 0

-- break lines at word boundaries
vim.opt.wrap = true
vim.opt.linebreak = true

-- copy the indent of the current line when inserting a new line
vim.opt.autoindent = true

-- disable inlay hints (they clutter the view)
vim.g.lazyvim_no_inlay_hints = true

-- disable autoformatting not to generate large diffs
vim.g.autoformat = false

-- list mode characters: dots for spaces/tabs and trailing spaces
vim.opt.listchars = {
  tab = "· ",
  trail = "·",
  nbsp = "+",
  extends = ">",
  precedes = "<",
}
