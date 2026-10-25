-- initkit: pin the treesitter parser list (see config/treesitter_parsers);
-- image builds pre-install all of them so no downloads are needed at runtime.
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = require("config.treesitter_parsers"),
  },
}
