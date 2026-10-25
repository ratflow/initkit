-- initkit: keymaps on top of LazyVim defaults
-- (terminal keymaps are registered by lua/plugins/terminal.lua)

-- copy the current file name to the system clipboard (OSC52-aware, so it
-- also works over ssh/tmux); C variant drops the extension
local copy_file_name = function(with_extension)
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")
  if not with_extension then
    name = vim.fn.fnamemodify(name, ":r")
  end
  vim.fn.setreg("+", name)
  vim.notify("Copied: " .. name)
end

vim.keymap.set("n", "<leader>fc", function()
  copy_file_name(true)
end, { desc = "Copy file name" })

vim.keymap.set("n", "<leader>fC", function()
  copy_file_name(false)
end, { desc = "Copy file name (no extension)" })
