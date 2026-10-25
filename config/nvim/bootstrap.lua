-- initkit bootstrap.lua - headless initialization used by image builds
-- and SHELL_INITS_NVIM_BOOTSTRAP=1 (see core/neovim.sh). Lives outside lua/
-- so it never loads during normal startup. Run AFTER "+Lazy! sync".
local parsers = require("config.treesitter_parsers")

local ok_ts, ts = pcall(require, "nvim-treesitter")
if ok_ts then
  pcall(ts.install, parsers)
end

-- prebuilt parsers download asynchronously; wait (max 5 min) until every
-- language on the list is usable
local missing = #parsers
local timed_out = not vim.wait(480000, function()
  missing = 0
  for _, lang in ipairs(parsers) do
    if not pcall(vim.treesitter.language.inspect, lang) then
      missing = missing + 1
    end
  end
  return missing == 0
end, 3000)

local found = #vim.api.nvim_get_runtime_file("parser/*.so", true)
print(("initkit bootstrap: %d/%d parsers ready, %d parser files in runtime, timed out: %s")
  :format(#parsers - missing, #parsers, found, tostring(timed_out)))
