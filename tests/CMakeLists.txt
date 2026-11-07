# The tests build inside the top-level project, which already loaded Clang and set C++17 for LLVM's headers.

# An archive and its hash, not a git clone: nothing here can ask for a credential on the runner.
include(FetchContent)
FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/release-1.12.1.tar.gz
    URL_HASH SHA256=81964fe578e9bd7c94dfdb09c8e4d6e6759e19967e397dbea48d1c10e45d0df2
)

set(gtest_force_shared_crt ON CACHE BOOL "" FORCE) # do not override the parent project's runtime settings on Windows
set(INSTALL_GTEST OFF)
set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)

# Always a static googletest, so the test binary needs no googletest DLL on Windows.
set(BUILD_SHARED_LIBS OFF)

FetchContent_MakeAvailable(googletest)

# Every .cpp directly in tests/. tests/tests_data holds the tool's inputs and is not compiled.
file(GLOB TEST_SRC_FILES "${CMAKE_SOURCE_DIR}/tests/*.cpp")

add_executable(refactor_tool_tests "${TEST_SRC_FILES}")
target_link_libraries(refactor_tool_tests PRIVATE gtest_main)
target_include_directories(refactor_tool_tests PRIVATE ${CMAKE_SOURCE_DIR}/include)

include(GoogleTest)
gtest_discover_tests(refactor_tool_tests)

# The manual list is judged where every other file is judged (section 9).
add_test(
    NAME manual_list
    COMMAND python -m pytest tests/test_manual_list.py -q -p no:cacheprovider
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
)
