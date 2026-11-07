# Manual

## Running the tool

The tool rewrites the files it is given, in place, so run it on a copy:

```powershell
Copy-Item tests\tests_data\test1.cpp $env:TEMP\test1.cpp
.\recipe.ps1 run $env:TEMP\test1.cpp --
```

The `--` ends the tool's own arguments: with nothing after it, Clang compiles the file with default flags and needs no `compile_commands.json`. On Windows the standard headers come from the MSVC environment that `recipe.ps1` imports.

As the template stands, the tool prints a remark for every destructor, method and variable it sees, exits 0 and leaves the file unchanged.

## The reference cases

| input | expected output | what changes |
| --- | --- | --- |
| `tests/tests_data/test1.cpp` | `test1_ref.cpp` | `virtual` on the destructor of a base class, once |
| `tests/tests_data/test2.cpp` | `test2_ref.cpp` | `override` on overriding methods |
| `tests/tests_data/test3.cpp` | `test3_ref.cpp` | `const auto&` instead of `const auto` in range-for |

`check_refactor.sh`, in Bash, runs `build/refactor_tool` on a copy of each input and compares it with `diff -w -B`. Today all three differ.

## The tests

`.\recipe.ps1 test` runs `ctest`: the one GoogleTest case and the check of `tests/manual/tests.json`. Nothing a person has to judge is listed there.
