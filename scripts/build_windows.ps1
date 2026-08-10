<#
.SYNOPSIS
    Builds refactor_tool and its unit tests natively on Windows with MSVC.

.DESCRIPTION
    The repository is normally built inside the Linux dev container
    (.devcontainer), where Clang/LLVM 20 comes from apt and `cl.exe` does not
    exist. This script is the Windows counterpart of that container: it is the
    single entry point that puts the MSVC toolchain into this process, points
    CMake at a Clang/LLVM development installation, configures the matching
    preset from CMakePresets.json, builds, runs the tests, and reports where the
    binaries went.

    The MSVC environment is imported into the current process rather than each
    command being wrapped in `cmd /c vcvars64 && ...`: Ninja invokes cl.exe
    dozens of times and every invocation has to see the same INCLUDE/LIB/PATH.

    Nothing here touches .devcontainer, and the script never falls back to a
    "half build" - every failure stops with an explanation of what to install
    or which switch to pass.

.PARAMETER BuildType
    Release (default) or Debug. Selects the matching CMake preset and its own
    build directory, so the two never overwrite each other.

.PARAMETER ClangInstallDir
    Root of a Clang/LLVM *development* installation, i.e. the directory that
    contains include\llvm and lib\cmake\clang\ClangConfig.cmake.

    This is deliberately a separate concept from "LLVM is installed": the
    LLVM-<ver>-win64.exe installer from llvm.org ships only the C API
    (include\llvm-c, libclang.lib) and cannot satisfy the
    `find_package(Clang REQUIRED CONFIG)` in CMakeLists.txt. The asset that can
    is clang+llvm-<ver>-x86_64-pc-windows-msvc.tar.xz from the same release.

.PARAMETER Clean
    Delete the preset's binary directory first, so the run proves the build
    works from scratch rather than from a warm cache.

.PARAMETER SkipTests
    Build everything but do not run the tests.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1 `
        -BuildType Debug -Clean `
        -ClangInstallDir 'C:\llvm\clang+llvm-20.1.8-x86_64-pc-windows-msvc'
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string] $BuildType = 'Release',

    [string] $ClangInstallDir = $env:CT_CLANG_INSTALL_DIR,

    [switch] $Clean,

    [switch] $SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Native executables do not raise PowerShell errors, so every external call is
# followed by this check. Without it a failed cmake would be reported as a
# successful build, which is the one outcome this script must never produce.
function Assert-NativeSuccess {
    param(
        [Parameter(Mandatory = $true)][string] $What
    )
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE."
    }
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$ConfigurePreset = if ($BuildType -eq 'Debug') { 'windows-msvc-debug' } else { 'windows-msvc-release' }
# Kept in step with the binaryDir of the presets above; the two Windows presets
# use separate directories on purpose, because a single Ninja build directory
# holds exactly one CMAKE_BUILD_TYPE.
$BinaryDirectory = if ($BuildType -eq 'Debug') {
    Join-Path $RepositoryRoot 'build\windows-debug'
} else {
    Join-Path $RepositoryRoot 'build\windows'
}

Write-Step "Repository root: $RepositoryRoot"
Write-Host "Build type: $BuildType (preset '$ConfigurePreset', directory '$BinaryDirectory')"

#-----------------------------------------------------------------------------
# 1. MSVC environment
#-----------------------------------------------------------------------------
# cl.exe is not on PATH in a normal shell; it only appears after vcvars64.bat
# has run. Rather than asking the user to open a "x64 Native Tools" prompt, the
# batch file is executed in a child cmd.exe and the environment it produces is
# imported back here, so this script works from any shell (and from a Telegram
# bot, CI runner or VS Code task).
function Enter-MsvcEnvironment {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) {
        Write-Host 'cl.exe already on PATH - reusing the current MSVC environment.'
        return
    }

    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vcvarsCandidates = New-Object System.Collections.Generic.List[string]

    if (Test-Path -LiteralPath $vsWhere) {
        # -latest with a C++ tools requirement, so a Visual Studio that was
        # installed without the desktop C++ workload is not reported as usable.
        $installationPath = & $vsWhere -latest -products '*' `
            -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' `
            -property installationPath
        if ($LASTEXITCODE -eq 0 -and $installationPath) {
            $vcvarsCandidates.Add((Join-Path ($installationPath | Select-Object -First 1) 'VC\Auxiliary\Build\vcvars64.bat'))
        }
    }

    foreach ($edition in 'Community', 'Professional', 'Enterprise', 'BuildTools') {
        foreach ($programFiles in ${env:ProgramFiles}, ${env:ProgramFiles(x86)}) {
            if ($programFiles) {
                $vcvarsCandidates.Add((Join-Path $programFiles "Microsoft Visual Studio\2022\$edition\VC\Auxiliary\Build\vcvars64.bat"))
            }
        }
    }

    $vcvars = $vcvarsCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $vcvars) {
        throw @'
No x64 MSVC environment found.

Install "Visual Studio 2022" (any edition, including the free Community) or the
standalone "Build Tools for Visual Studio 2022", with the workload
"Desktop development with C++", then re-run this script. Looked for
VC\Auxiliary\Build\vcvars64.bat under every Visual Studio 2022 installation.
'@
    }

    Write-Host "Importing MSVC environment from: $vcvars"
    $environmentDump = & "$env:ComSpec" /c "call `"$vcvars`" >nul 2>&1 && set"
    Assert-NativeSuccess -What "vcvars64.bat ($vcvars)"

    foreach ($line in $environmentDump) {
        # PATH and friends contain '=' in their values, so only the first one
        # separates the name from the value.
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $name = $line.Substring(0, $separator)
            $value = $line.Substring($separator + 1)
            Set-Item -LiteralPath "env:$name" -Value $value
        }
    }

    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
        throw "vcvars64.bat ran but cl.exe is still not on PATH. The Visual Studio installation at '$vcvars' looks incomplete; repair it in the Visual Studio Installer."
    }
}

Write-Step 'Entering the MSVC x64 environment'
Enter-MsvcEnvironment
# Deliberately reporting the path instead of running `cl.exe` for its banner:
# cl writes that banner to stderr, and Windows PowerShell turns native stderr
# into error records, which $ErrorActionPreference = 'Stop' would treat as a
# failed build.
Write-Host "cl.exe: $((Get-Command cl.exe).Source)"

# Checked after vcvars, not before: on many machines cmake and ninja arrive with
# the Visual Studio component "C++ CMake tools for Windows" and only appear on
# PATH once the developer environment has been imported.
foreach ($required in 'cmake', 'ninja', 'ctest') {
    if (-not (Get-Command $required -ErrorAction SilentlyContinue)) {
        throw "'$required' was not found on PATH. Install it (winget install Kitware.CMake / Ninja-build.Ninja) or add the Visual Studio component 'C++ CMake tools for Windows'."
    }
}

#-----------------------------------------------------------------------------
# 2. Clang/LLVM development installation
#-----------------------------------------------------------------------------
# CMakeLists.txt links clangTooling/clangBasic/clangASTMatchers, so it needs the
# C++ headers and static libraries, not just clang.exe.
function Test-ClangDevelopmentTree {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Candidate)
    if (-not $Candidate) { return $false }
    if (-not (Test-Path -LiteralPath $Candidate)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Candidate 'include\llvm')) -and
           (Test-Path -LiteralPath (Join-Path $Candidate 'lib\cmake\clang\ClangConfig.cmake'))
}

function Resolve-ClangInstallDir {
    param([AllowEmptyString()][string] $Explicit)

    if ($Explicit) {
        if (-not (Test-ClangDevelopmentTree -Candidate $Explicit)) {
            throw @"
'$Explicit' is not a Clang/LLVM development installation.

Expected to find both of these underneath it:
  include\llvm
  lib\cmake\clang\ClangConfig.cmake
"@
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    # Ordered guesses. Anything found by chance is still validated above, so a
    # partial installation is reported as missing rather than used.
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:LLVM_HOME) { $candidates.Add($env:LLVM_HOME) }
    foreach ($programFiles in ${env:ProgramFiles}, ${env:ProgramFiles(x86)}) {
        if ($programFiles) { $candidates.Add((Join-Path $programFiles 'LLVM')) }
    }
    foreach ($root in 'C:\llvm', 'C:\LLVM') { $candidates.Add($root) }
    foreach ($searchRoot in 'C:\', 'C:\llvm', $env:LOCALAPPDATA) {
        if (-not $searchRoot) { continue }
        foreach ($found in Get-ChildItem -Path $searchRoot -Directory -Filter 'clang+llvm-*windows-msvc' -ErrorAction SilentlyContinue) {
            $candidates.Add($found.FullName)
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-ClangDevelopmentTree -Candidate $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw @'
No Clang/LLVM development installation found.

CMakeLists.txt calls find_package(Clang REQUIRED CONFIG) and links
clangTooling / clangBasic / clangASTMatchers, so it needs LLVM's C++ headers
and libraries (LLVM 19 or newer).

Note that the usual LLVM-<version>-win64.exe installer is NOT enough: it ships
only clang.exe plus the C API (include\llvm-c, libclang.lib) and has no
lib\cmake\clang\ClangConfig.cmake.

Download the development distribution from the same GitHub release, e.g.

  https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz

unpack it anywhere (tar -xJf <file>), then either pass

  -ClangInstallDir <unpacked directory>

or set the CT_CLANG_INSTALL_DIR environment variable to it.
'@
}

Write-Step 'Locating a Clang/LLVM development installation'
$ResolvedClangInstallDir = Resolve-ClangInstallDir -Explicit $ClangInstallDir
Write-Host "Using Clang/LLVM from: $ResolvedClangInstallDir"

# CMakePresets.json reads this through $env{CT_CLANG_INSTALL_DIR}; forward
# slashes because CMake treats a trailing backslash in a cache value as an
# escape character.
$env:CT_CLANG_INSTALL_DIR = $ResolvedClangInstallDir.Replace('\', '/')

#-----------------------------------------------------------------------------
# 3. Clean
#-----------------------------------------------------------------------------
# Deliberately before the dependency step below: a Conan toolchain file is
# generated *inside* the build directory, so wiping the directory afterwards
# would delete it and the configure step would then fail to find it.
if ($Clean -and (Test-Path -LiteralPath $BinaryDirectory)) {
    Write-Step "Removing $BinaryDirectory (clean build requested)"
    Remove-Item -LiteralPath $BinaryDirectory -Recurse -Force
}

#-----------------------------------------------------------------------------
# 4. Conan (only if this repository actually uses it)
#-----------------------------------------------------------------------------
# Several sibling repositories declare their dependencies with Conan; this one
# fetches GoogleTest with FetchContent and takes Clang/LLVM from the
# installation located above. Running `conan install` anyway would fail on a
# missing recipe, so the step is driven by the files on disk.
$ExtraConfigureArguments = @()
$conanRecipe = 'conanfile.py', 'conanfile.txt' |
    ForEach-Object { Join-Path $RepositoryRoot $_ } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if ($conanRecipe) {
    Write-Step "Installing Conan dependencies ($(Split-Path -Leaf $conanRecipe))"
    if (-not (Get-Command conan -ErrorAction SilentlyContinue)) {
        throw "This repository has $(Split-Path -Leaf $conanRecipe) but 'conan' is not on PATH. Install it with: pip install conan"
    }

    # A machine that has never run Conan has no default profile, and `conan
    # install` then dies with "profile 'default' not found"; detecting it is
    # idempotent and cheap, so it is safe to do unconditionally.
    & conan profile detect --force | Out-Host
    Assert-NativeSuccess -What 'conan profile detect'

    # tools.cmake.cmaketoolchain:generator=Ninja is not optional: left to its
    # own devices Conan assumes a Visual Studio generator on Windows and writes
    # `set(CMAKE_GENERATOR_PLATFORM x64 ... FORCE)` into conan_toolchain.cmake,
    # which Ninja rejects with "does not support platform specification".
    $conanOutputFolder = Join-Path $BinaryDirectory 'conan'
    & conan install $RepositoryRoot --output-folder $conanOutputFolder --build missing `
        -s "build_type=$BuildType" `
        -c tools.cmake.cmaketoolchain:generator=Ninja | Out-Host
    Assert-NativeSuccess -What 'conan install'

    $conanToolchain = Join-Path $conanOutputFolder 'conan_toolchain.cmake'
    if (-not (Test-Path -LiteralPath $conanToolchain)) {
        throw "conan install finished but '$conanToolchain' was not generated; the recipe is probably missing the CMakeToolchain generator."
    }
    $ExtraConfigureArguments += "-DCMAKE_TOOLCHAIN_FILE=$($conanToolchain.Replace('\','/'))"
}
else {
    Write-Step 'Skipping Conan: this repository has no conanfile (GoogleTest arrives through FetchContent)'
}

#-----------------------------------------------------------------------------
# 5. Configure and build
#-----------------------------------------------------------------------------
# `cmake --preset` looks for CMakePresets.json in the *current* directory, not
# next to any -S argument, so the preset-driven calls all run from the
# repository root and the caller's directory is restored afterwards.
Push-Location -LiteralPath $RepositoryRoot
try {
    Write-Step "Configuring preset '$ConfigurePreset'"
    & cmake --preset $ConfigurePreset @ExtraConfigureArguments | Out-Host
    Assert-NativeSuccess -What "cmake --preset $ConfigurePreset"

    Write-Step "Building preset '$ConfigurePreset'"
    & cmake --build --preset $ConfigurePreset | Out-Host
    Assert-NativeSuccess -What "cmake --build --preset $ConfigurePreset"
}
finally {
    Pop-Location
}

#-----------------------------------------------------------------------------
# 6. Report - and verify the report is true
#-----------------------------------------------------------------------------
# "Build succeeded" is only believable if the artefacts are on disk, so the
# paths that get printed are the ones that were actually found.
Write-Step 'Produced binaries'
$producedBinaries = @(Get-ChildItem -LiteralPath $BinaryDirectory -Filter '*.exe' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'refactor_tool*' })

if (-not $producedBinaries) {
    throw "The build reported success but no refactor_tool*.exe was found in '$BinaryDirectory'."
}
foreach ($binary in $producedBinaries) {
    Write-Host ('  {0}  ({1:N0} bytes)' -f $binary.FullName, $binary.Length) -ForegroundColor Green
}

#-----------------------------------------------------------------------------
# 7. Tests
#-----------------------------------------------------------------------------
if (-not $SkipTests) {
    Write-Step "Running tests (ctest, preset '$ConfigurePreset')"
    Push-Location -LiteralPath $RepositoryRoot
    try {
        # --no-tests=error rather than the default: ctest exits 0 when it finds
        # nothing to run, so without this a build whose tests silently stopped
        # being registered would still be reported here as "tests passed".
        & ctest --preset $ConfigurePreset --no-tests=error | Out-Host
        Assert-NativeSuccess -What "ctest --preset $ConfigurePreset"
    }
    finally {
        Pop-Location
    }
}

Write-Step 'Done'
Write-Host "Try it out:  $(Join-Path $BinaryDirectory 'refactor_tool.exe') tests\tests_data\for_refactor.cpp --" -ForegroundColor Green
