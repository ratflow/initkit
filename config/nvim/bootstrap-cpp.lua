-- shell-inits bootstrap-cpp.lua - headless verification of the C++ layer,
-- used by image builds (see core/cpp-dev.sh). Lives outside lua/ so it never
-- loads during normal startup. Run AFTER "+Lazy! sync"; exits with :cquit when
-- anything is missing so docker builds fail loudly instead of shipping broken
-- images.
local expected_plugins = {
  ["clangd_extensions.nvim"] = true, -- clangd LSP extras
  ["conform.nvim"] = true, -- clang-format integration
  ["nvim-dap"] = true, -- debugger core
  ["nvim-dap-ui"] = true, -- debugger UI
  ["nvim-dap-virtual-text"] = true, -- inline values while debugging
  ["neotest"] = true, -- test runner
  ["neotest-gtest"] = true, -- GoogleTest adapter
}

local problems = {}

local plugins = require("lazy.core.config").plugins
for name in pairs(expected_plugins) do
  if not plugins[name] then
    table.insert(problems, "missing plugin: " .. name)
  end
end

for _, exe in ipairs({ "clangd", "clang-format", "codelldb", "cmake", "bear", "ninja" }) do
  if vim.fn.exepath(exe) == "" then
    table.insert(problems, "missing executable: " .. exe)
  end
end

if #problems > 0 then
  print("shell-inits cpp bootstrap FAILED:\n  " .. table.concat(problems, "\n  "))
  vim.cmd("cquit 1")
end

print(("shell-inits cpp bootstrap: %d plugins + 6 toolchain binaries verified")
  :format(vim.tbl_count(expected_plugins)))
