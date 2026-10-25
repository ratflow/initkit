# cpp-sample

A minimal C++ project showing the whole toolchain wired together: cmake +
ninja build, vcpkg dependency management (GoogleTest), clangd code
intelligence, and debugging with codelldb. It is pre-built in the docker
image, so everything below also works offline.

## Layout

```
CMakeLists.txt        - library + app + gtest suite
CMakePresets.json     - debug/release presets wired to the vcpkg toolchain
vcpkg.json            - manifest: dependencies pulled by vcpkg (gtest)
.clang-format         - style picked up by `clang-format` / nvim formatting
include/, src/, tests/
compile_commands.json - symlink into build/debug/, used by clangd
```

## Build, run, test

```sh
cmake --preset debug          # configure (vcpkg installs gtest on first run)
cmake --build --preset debug  # compile
./build/debug/cpp-sample      # run the app
ctest --preset debug          # run the unit tests
```

The presets read `$VCPKG_ROOT` (set to /opt/vcpkg in the image). After
changing `vcpkg.json`, just re-configure; vcpkg restores previously built
packages from its binary cache, so no downloads are needed for the same
dependency set.

## From nvim (LazyVim)

Open the project (`nvim .` from this directory) and:

- **LSP**: clangd attaches automatically (compile_commands.json is in the
  project root). `gd` definition, `gr` references, `K` hover,
  `<leader>ch` switch source/header, `<leader>cr` rename.
- **Format**: `<leader>cf` runs clang-format (uses .clang-format).
- **Debug**: put a breakpoint on the `result *= i;` line in src/calc.cpp
  (`<leader>db`), then `<leader>dc` (Run/Continue), pick the executable
  `./build/debug/cpp-sample`; dap-ui opens, step with `<leader>di` /
  `<leader>dO`.
- **Tests**: `<leader>tr` runs the nearest GoogleTest case,
  `<leader>tt` the whole file, `<leader>td` debugs the nearest one. The test
  executable mapping (tests/ -> build/debug/unit_tests) is preconfigured; for
  new projects use `:ConfigureGtest` in the neotest summary window
  (`<leader>ts`).

## Non-cmake projects

For plain Makefile projects, generate compile_commands.json for clangd with:

```sh
bear -- make
```

## Add a dependency

Add it to `vcpkg.json` (`"dependencies": ["gtest", "fmt"]`) and reconfigure.
Use `vcpkg search <name>` (on PATH in the image) to discover packages.
