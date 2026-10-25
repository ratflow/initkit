-- shell-inits: test layer (deployed by core/cpp-dev.sh, set: dev-cpp-neovim;
-- the neotest core extra itself is imported by config/lazy.lua).
-- neotest + the GoogleTest adapter, matching the vcpkg/gtest sample project.
--
-- neotest-gtest is pinned to the last commit that supports nvim 0.11 (which is
-- what ubuntu-26.04 ships); drop the pin once the distro neovim is >= 0.12.
return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "alfaix/neotest-gtest",
        version = "b66f1d33cbf3b37b9803e6bc7ef47ac60eba86b1",
      },
    },
    opts = {
      adapters = {
        ["neotest-gtest"] = {
          debug_adapter = "codelldb",
        },
      },
    },
  },
}
