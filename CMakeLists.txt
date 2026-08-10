cmake_minimum_required(VERSION 3.20)
project(clang-tutor)

#===============================================================================
# 0. GET CLANG INSTALLATION DIR
#===============================================================================
# In clang-tutor, `CT_Clang_INSTALL_DIR` is the key CMake variable - it points
# to a Clang installation directory. For the sake of completeness,
# <PackageName>_DIR (i.e. `Clang_DIR`) and <PackageName>_ROOT (i.e.
# `Clang_ROOT`) are also supported. Visit CMake documentation for more details:
#   https://cmake.org/cmake/help/latest/command/find_package.html
# Use only _one_ of these variables.

if(DEFINED Clang_ROOT)
  set(CT_CLANG_PACKAGE_DIR "${Clang_ROOT}/../../..")
elseif(DEFINED Clang_DIR)
  set(CT_CLANG_PACKAGE_DIR "${Clang_DIR}/../../..")
endif()
mark_as_advanced(CT_CLANG_PACKAGE_DIR)

# Set this to a valid Clang installation directory. This is most likely where
# LLVM is installed on your system.
set(CT_Clang_INSTALL_DIR "${CT_CLANG_PACKAGE_DIR}" CACHE PATH
  "Clang installation directory")

#===============================================================================
# 1. VERIFY CLANG INSTALLATION DIR
#===============================================================================
set(CT_LLVM_INCLUDE_DIR "${CT_Clang_INSTALL_DIR}/include/llvm")
if(NOT EXISTS "${CT_LLVM_INCLUDE_DIR}")
message(FATAL_ERROR
  " CT_Clang_INSTALL_DIR (${CT_LLVM_INCLUDE_DIR}) is invalid.")
endif()

set(CT_LLVM_CMAKE_FILE
  "${CT_Clang_INSTALL_DIR}/lib/cmake/clang/ClangConfig.cmake")
if(NOT EXISTS "${CT_LLVM_CMAKE_FILE}")
message(FATAL_ERROR
  " CT_LLVM_CMAKE_FILE (${CT_LLVM_CMAKE_FILE}) is invalid.")
endif()

#===============================================================================
# 2. LOAD CLANG CONFIGURATION
#    Extracted from:
#    http://llvm.org/docs/CMake.html#embedding-llvm-in-your-project
#===============================================================================
list(APPEND CMAKE_PREFIX_PATH "${CT_Clang_INSTALL_DIR}/lib/cmake/clang/")

find_package(Clang REQUIRED CONFIG)

# Sanity check. As Clang does not expose e.g. `CLANG_VERSION_MAJOR` through
# AddClang.cmake, we have to use LLVM_VERSION_MAJOR instead.
# TODO: Revisit when next version is released.
if("${LLVM_VERSION_MAJOR}" VERSION_LESS 19)
  message(FATAL_ERROR "Found LLVM ${LLVM_VERSION_MAJOR}, but need LLVM 19 or above")
endif()

message(STATUS "Found Clang ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using ClangConfig.cmake in: ${CT_Clang_INSTALL_DIR}")

#===============================================================================
# 2a. REPAIR THE DIA SDK PATH BAKED INTO LLVM's WINDOWS BINARY RELEASE
#===============================================================================
# LLVMExports.cmake is generated on llvm.org's release machine, and for
# LLVMDebugInfoPDB it records the *absolute* path of the diaguids.lib that
# machine happened to have (a Visual Studio 2019 Professional DIA SDK). That
# path is a hard dependency in the generated build system, so on any other
# Windows box the build dies before compiling anything, with
#   ninja: error: '.../2019/Professional/DIA SDK/lib/amd64/diaguids.lib',
#          needed by 'refactor_tool.exe', missing and no known rule to make it
# The fix is to swap that one stale entry for the DIA SDK of the Visual Studio
# actually installed here. Nothing outside Windows/MSVC is touched, so the
# dev-container build is unaffected.
if(MSVC AND TARGET LLVMDebugInfoPDB)
  get_target_property(CT_PDB_LINK_LIBRARIES LLVMDebugInfoPDB INTERFACE_LINK_LIBRARIES)

  set(CT_PDB_LINK_LIBRARIES_FIXED "")
  set(CT_DIA_SDK_REPAIRED FALSE)
  foreach(CT_PDB_LINK_ITEM IN LISTS CT_PDB_LINK_LIBRARIES)
    # Only absolute paths can go stale; plain target names such as LLVMSupport
    # are resolved by CMake and must be passed through untouched.
    if(IS_ABSOLUTE "${CT_PDB_LINK_ITEM}" AND NOT EXISTS "${CT_PDB_LINK_ITEM}")
      get_filename_component(CT_MISSING_LIBRARY_NAME "${CT_PDB_LINK_ITEM}" NAME_WE)

      # VSINSTALLDIR is exported by vcvars64.bat (scripts/build_windows.ps1
      # imports it); deriving the root from cl.exe as well keeps this working in
      # a Developer PowerShell or a VS generator run, where it may be unset.
      # cl.exe lives at <VS>/VC/Tools/MSVC/<version>/bin/Host<arch>/<arch>/cl.exe,
      # i.e. seven directory levels below the Visual Studio root.
      get_filename_component(CT_VS_ROOT_FROM_COMPILER "${CMAKE_CXX_COMPILER}" DIRECTORY)
      foreach(CT_UNUSED_INDEX RANGE 6)
        get_filename_component(CT_VS_ROOT_FROM_COMPILER "${CT_VS_ROOT_FROM_COMPILER}" DIRECTORY)
      endforeach()

      unset(CT_DIA_SDK_LIBRARY CACHE)
      find_library(CT_DIA_SDK_LIBRARY
        NAMES "${CT_MISSING_LIBRARY_NAME}"
        HINTS
          "$ENV{VSINSTALLDIR}/DIA SDK/lib/amd64"
          "${CT_VS_ROOT_FROM_COMPILER}/DIA SDK/lib/amd64"
        NO_DEFAULT_PATH)

      if(NOT CT_DIA_SDK_LIBRARY)
        message(FATAL_ERROR
          " LLVMDebugInfoPDB refers to '${CT_PDB_LINK_ITEM}', which does not\n"
          " exist on this machine, and no replacement '${CT_MISSING_LIBRARY_NAME}'\n"
          " was found in the local DIA SDK. Install the 'Desktop development\n"
          " with C++' workload of Visual Studio (it ships <VS>/DIA SDK), or run\n"
          " this build from a Visual Studio developer prompt so that VSINSTALLDIR\n"
          " is set.")
      endif()

      message(STATUS "Repointing ${CT_MISSING_LIBRARY_NAME} to ${CT_DIA_SDK_LIBRARY}")
      list(APPEND CT_PDB_LINK_LIBRARIES_FIXED "${CT_DIA_SDK_LIBRARY}")
      set(CT_DIA_SDK_REPAIRED TRUE)
    else()
      list(APPEND CT_PDB_LINK_LIBRARIES_FIXED "${CT_PDB_LINK_ITEM}")
    endif()
  endforeach()

  if(CT_DIA_SDK_REPAIRED)
    set_target_properties(LLVMDebugInfoPDB PROPERTIES
      INTERFACE_LINK_LIBRARIES "${CT_PDB_LINK_LIBRARIES_FIXED}")
  endif()
endif()

message("CLANG STATUS:
  Includes (clang)    ${CLANG_INCLUDE_DIRS}
  Includes (llvm)     ${LLVM_INCLUDE_DIRS}"
)

# Set the LLVM and Clang header and library paths
include_directories(SYSTEM "${LLVM_INCLUDE_DIRS};${CLANG_INCLUDE_DIRS}")

#===============================================================================
# 3. CLANG-TUTOR BUILD CONFIGURATION
#===============================================================================
# Use the same C++ standard as LLVM does
set(CMAKE_CXX_STANDARD 17 CACHE STRING "")

# Build type
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Debug CACHE
      STRING "Build type (default Debug):" FORCE)
endif()

# Compiler flags
if(MSVC)
  # cl.exe silently accepts "-Wall" as its own /Wall and then buries the build
  # in warnings raised inside LLVM's own headers, and it has no
  # -fdiagnostics-color at all, so the GCC/Clang flags are replaced here rather
  # than reused. /utf-8 is not cosmetic: the sources carry Russian diagnostic
  # text, and without it MSVC decodes these UTF-8 files with the system ANSI
  # code page and emits mojibake (or C2001 on a split multi-byte sequence).
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W3 /utf-8")
else()
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall\
    -fdiagnostics-color=always")
endif()

# LLVM/Clang is normally built without RTTI. Be consistent with that.
if(NOT LLVM_ENABLE_RTTI)
  if(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /GR-")
  else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-rtti")
  endif()
endif()

# -fvisibility-inlines-hidden is set when building LLVM and on Darwin warnings
# are triggered if llvm-tutor is built without this flag (though otherwise it
# builds fine). For consistency, add it here too.
# MSVC is excluded: it has no equivalent of this flag, and a failed
# check_cxx_compiler_flag leaves the result variable empty, which turns the
# unquoted `if(${...} EQUAL "1")` below into a CMake syntax error before the
# project can even be configured.
if(NOT MSVC)
  include(CheckCXXCompilerFlag)
  check_cxx_compiler_flag("-fvisibility-inlines-hidden"
    SUPPORTS_FVISIBILITY_INLINES_HIDDEN_FLAG)
  if(${SUPPORTS_FVISIBILITY_INLINES_HIDDEN_FLAG} EQUAL "1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fvisibility-inlines-hidden")
  endif()
endif()

# Set the build directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}")

# tests/CMakeLists.txt already calls gtest_discover_tests(), but the tests it
# registers are only written to a CTestTestfile.cmake if testing is enabled at
# the top of the tree. Without this line `ctest` prints "No tests were found!!!"
# and - worse - still exits 0, so the test presets in CMakePresets.json would
# report a pass while running nothing at all.
enable_testing()

#===============================================================================
# 4. ADD SUB-TARGETS
# Doing this at the end so that all definitions and link/include paths are
# available for the sub-projects.
#===============================================================================
add_subdirectory(tests)
add_subdirectory(src)


