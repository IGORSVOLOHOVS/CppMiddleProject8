# Install

The tool needs no installing: `.\recipe.ps1 build` leaves `build\refactor_tool.exe`, and `.\recipe.ps1 install` does nothing.

To build and test it here:

1. Install Visual Studio 2022, any edition, with the "Desktop development with C++" workload. `recipe.ps1` finds it with `vswhere` and imports `vcvars64.bat` itself, so no developer prompt is needed.
2. Download `clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz` from the LLVM 20.1.8 release and unpack it under `C:\LLVM`. The usual `LLVM-<version>-win64.exe` installer is not enough: it has no `lib\cmake\clang\ClangConfig.cmake`. Windows' own `tar` cannot read `.xz`, so unpack with `python -m tarfile -e <archive> C:\LLVM`. Elsewhere, set `CT_CLANG_INSTALL_DIR` to the tree.
3. Install CMake 3.20 or newer, Ninja, and LLVM from its installer for `clang-tidy` and `clang-format` in `C:\Program Files\LLVM\bin`.
4. Clone this repository and run `.\recipe.ps1 test`. The first run downloads GoogleTest, whose archive `tests/CMakeLists.txt` pins by hash.

The build is Release with the `/MD` runtime, because llvm.org builds its Windows libraries that way; a Debug runtime fails to link with `LNK2038`.

## Other routes

`.devcontainer` builds in Docker on Linux with LLVM 20 from apt.llvm.org, `CMakePresets.json` names a Linux and two MSVC presets, and `scripts/build_windows.ps1` drives the MSVC ones. These are what the course and the old GitHub route left. No gate runs them.
