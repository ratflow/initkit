-- initkit: subtle pastel rainbow indent guides, no scope line.
-- The IblIndentN groups are defined here (catppuccin does not ship them and
-- ibl refuses to start when they are missing). Static catppuccin macchiato
-- colors, re-applied on every colorscheme switch.
local define_highlights = function()
  local palette = { "#8aadf4", "#c6a0f6", "#f5bde6", "#a6da95", "#eed49f", "#8bd5ca" }
  for i, color in ipairs(palette) do
    vim.api.nvim_set_hl(0, ("IblIndent%d"):format(i), { fg = color, nocombine = true })
  end
  vim.api.nvim_set_hl(0, "IblIndent", { fg = "#6e738d", nocombine = true })
end

return {
  "lukas-reineke/indent-blankline.nvim",
  main = "ibl",
  init = function()
    define_highlights()
    vim.api.nvim_create_autocmd("ColorScheme", { callback = define_highlights })
  end,
  opts = {
    indent = {
      highlight = {
        "IblIndent",
        "IblIndent1",
        "IblIndent2",
        "IblIndent3",
        "IblIndent4",
        "IblIndent5",
        "IblIndent6",
      },
    },
    scope = { enabled = false },
  },
}
