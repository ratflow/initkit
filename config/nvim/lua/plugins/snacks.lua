-- shell-inits: snacks.nvim tweaks - explorer/picker visibility, notifications
return {
  "folke/snacks.nvim",
  opts = {
    notifier = {
      timeout = 10000,
    },
    picker = {
      hidden = true,
      ignored = true,
      sources = {
        explorer = {
          lazy = true,
          hidden = true,
          ignored = true,
          exclude = {
            "**/.git",
            "**/.DS_Store",
          },
          -- Yank paths from the explorer: Y relative, gy absolute
          win = {
            list = {
              keys = {
                ["Y"] = "copy_relative",
                ["gy"] = "copy_absolute",
                ["L"] = { { "pick_win", "jump" }, mode = { "n", "i" } },
              },
            },
          },
          actions = {
            copy_absolute = function(_, item)
              local path = item.file
              vim.fn.setreg('"', path)
              vim.fn.setreg("+", path)
              Snacks.notify.info("Copied absolute path: " .. path)
            end,
            copy_relative = function(_, item)
              local path = vim.fn.fnamemodify(item.file, ":.")
              vim.fn.setreg('"', path)
              vim.fn.setreg("+", path)
              Snacks.notify.info("Copied relative path: " .. path)
            end,
          },
        },
        files = {
          hidden = true,
        },
      },
    },
  },
}
