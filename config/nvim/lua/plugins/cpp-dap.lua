-- initkit: debugger layer (deployed by core/cpp-dev.sh, set: dev-cpp-neovim;
-- the dap core extra itself is imported by config/lazy.lua). codelldb is
-- installed system-wide by core/cpp-dev.sh (/usr/local/bin), so the default
-- adapter ("codelldb" resolved from PATH) needs no mason download and
-- debugging works offline.
return {
  -- the clangd extra asks mason to ensure-install codelldb; drop that again,
  -- we ship the binary outside of mason (see config/nvim/lua/plugins/cpp-clangd.lua)
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = vim.tbl_filter(function(pkg)
        return pkg ~= "codelldb"
      end, opts.ensure_installed or {})
    end,
  },

  -- never try to install debug adapters through mason at debug time (network)
  {
    "jay-babu/mason-nvim-dap.nvim",
    optional = true,
    opts = {
      automatic_installation = false,
    },
  },

  -- codelldb listens on IPv4 only, while `localhost` may resolve to ::1 first
  -- (making every connect fail with ECONNREFUSED); pin the loopback address
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      if type(dap.adapters.codelldb) == "table" then
        dap.adapters.codelldb.host = "127.0.0.1"
      end
    end,
  },
}
