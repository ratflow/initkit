-- shell-inits: OSC 52 clipboard whenever there is no local clipboard tool -
-- that covers ssh sessions (SSH_TTY) and containers/VMs without xclip/wl-copy.
--
-- Inside tmux, copies are routed through ~/.config/tmux/osc52-copy.sh, which
-- writes the escape sequence to the attached client terminals directly:
-- tmux's own pane-OSC52 forwarding is unreliable across versions. Outside
-- tmux the sequence simply goes to stdout (the terminal itself).
local has_clipboard_tool = function()
  local tools = { "xclip", "xsel", "wl-copy", "wl-paste", "pbcopy", "win32yank", "clip.exe" }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool) == 1 then
      return true
    end
  end
  return false
end

if vim.env.SSH_TTY or not has_clipboard_tool() then
  local osc52 = require("vim.ui.clipboard.osc52")
  local helper = vim.fn.expand("~/.config/tmux/osc52-copy.sh")

  local make_copy
  if vim.env.TMUX and vim.fn.executable(helper) == 1 and vim.system then
    make_copy = function()
      return function(lines, _)
        -- errors here would break yanking; the helper is best effort
        pcall(function()
          vim.system({ helper }, { stdin = table.concat(lines, "\n") }):wait()
        end)
      end
    end
  else
    make_copy = function(reg)
      return osc52.copy(reg)
    end
  end

  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = make_copy("+"),
      ["*"] = make_copy("*"),
    },
    paste = {
      -- paste needs the terminal to answer an OSC 52 query; unsupported
      -- terminals just yield an empty paste.
      ["+"] = osc52.paste("+"),
      ["*"] = osc52.paste("*"),
    },
  }
end

vim.opt.clipboard = "unnamedplus"
