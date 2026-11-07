# cpp-middle-project8

A refactoring tool on Clang LibTooling: `refactor_tool <file.cpp> --` parses a C++ file with Clang 20, matches its AST and rewrites the file in place. It began as the course template of sprint 8 of the Yandex Practicum "Middle C++ developer" course, which asks for three refactorings:

- add `virtual` to the destructor of a class that is a base class,
- add `override` to a method that overrides one and does not say so,
- make the loop variable of a range-for over objects a `const` reference.

The template is not finished. `src/RefactorTool.cpp` still holds the course's `todo` markers: its matchers match every destructor, method and variable, and its handlers report a remark for each and rewrite nothing. `tests/tests_data` holds the three inputs and the output each should become, and `check_refactor.sh` compares them, so the work left is written down where it will be judged.

## Layout

```text
include/            RefactorTool.h, the match callback, the AST consumer and the frontend action
src/                RefactorTool.cpp, the matchers, the handlers and main
tests/              the GoogleTest binary and the manual-list check
tests/tests_data/   the tool's inputs and their expected outputs, never compiled
```

## Build and test

`.\recipe.ps1 test` imports the MSVC environment, configures against the Clang/LLVM development tree, builds the tool and its tests, runs `ctest`, `clang-tidy` and `clang-format`, and searches `include` and `src` for locks and for `throw`, `try` and `catch`. It needs Visual Studio 2022 with the C++ workload, the `clang+llvm-20.1.8-x86_64-pc-windows-msvc` archive unpacked under `C:\LLVM`, cmake, ninja and LLVM's `clang-tidy` and `clang-format`. `docs/install.md` has the details, and `docs/manual.md` shows how to run the tool.

MIT licensed: `LICENSE` is the course's, copyright Yandex Practicum.
