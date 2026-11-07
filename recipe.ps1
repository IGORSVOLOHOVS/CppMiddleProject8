param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('build', 'install', 'uninstall', 'clean', 'run', 'publish', 'info', 'test')]
    [string]$Verb,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RunArgs
)

# Everything down to $OverridePhrase is read as TEXT by the git hooks and the
# pipeline: one literal per line, no variables, no concatenation.
$Name    = 'cpp-middle-project8'# the repository, lower-case kebab-case
$Code    = 'cmp8'               # the project code; the first word of every branch
$Version = '1.0.0'
$Summary = 'A Clang LibTooling refactoring tool in C++: the course template for virtual destructors, override and references in range-for.'
$Needs   = @()                   # other lab projects, name@tag - this one depends on none
$Tools   = @()                   # toolchains the lab must fetch - MSVC, the Clang/LLVM development tree, cmake and ninja are on the machine

# A console tool taken as a library on purpose: no $App, no installer.
# The computational core: what `publish` hands over, what the wiki reads, and where `test` allows no lock and no exception.
$Provides = @('include', 'src')

$CommitTypes  = @('feat', 'fix', 'docs', 'refactor', 'test', 'build', 'ci', 'chore')
$CommitScopes = @('core', 'build', 'ci', 'docs', 'deps')
$BranchTypes  = @('feat', 'fix', 'docs', 'refactor', 'test', 'build', 'ci', 'chore', 'hotfix', 'experiment')
$Reviewers    = @('igors')
$OverridePhrase = '1234567890'   # section 8 - the owner's override; a mark, not a password

# Native tools report on stderr and their exit code is the verdict, so a line on stderr must not stop the verb.
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot

# ValueFromRemainingArguments leaves $RunArgs null when nothing follows the verb.
if ($null -eq $RunArgs) { $RunArgs = @() }

# .claude/.env is gitignored here and never committed. A variable already set wins.
$envFile = Join-Path $PSScriptRoot '.claude\.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content -Encoding UTF8 $envFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$' -and
            -not (Test-Path "env:$($Matches[1])")) {
            Set-Item "env:$($Matches[1])" $Matches[2].Trim('"', "'")
        }
    }
}

# clang-tidy and clang-format come from the LLVM installer; the runner starts without that folder on PATH.
if (Test-Path 'C:\Program Files\LLVM\bin') { $env:Path = "C:\Program Files\LLVM\bin;$env:Path" }

function Enter-Msvc {
    # llvm.org's Windows development tree is built by MSVC against /MD, so only cl.exe links against it.
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return }
    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vsWhere)) { Write-Host 'vswhere.exe is missing: install Visual Studio 2022 with the C++ workload.'; exit 1 }
    $vs = & $vsWhere -latest -products '*' -requires 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' -property installationPath
    $vcvars = Join-Path "$vs" 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not $vs -or -not (Test-Path $vcvars)) { Write-Host 'No Visual Studio with the x64 C++ tools was found.'; exit 1 }
    # Each line of `set` after vcvars64 is NAME=VALUE, and only the first '=' separates them.
    foreach ($line in (& "$env:ComSpec" /c "call `"$vcvars`" >nul 2>&1 && set")) {
        $at = $line.IndexOf('=')
        if ($at -gt 0) { Set-Item -LiteralPath "env:$($line.Substring(0, $at))" -Value $line.Substring($at + 1) }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { Write-Host 'vcvars64.bat ran and cl.exe is still not on PATH.'; exit 1 }
}

function Find-ClangTree {
    # The tree that holds lib\cmake\clang\ClangConfig.cmake: the release archive, not the LLVM installer.
    $candidates = @($env:CT_CLANG_INSTALL_DIR) + @(Get-ChildItem -Directory 'C:\LLVM\clang+llvm-*-windows-msvc' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object FullName)
    foreach ($tree in $candidates) {
        if ($tree -and (Test-Path (Join-Path $tree 'lib\cmake\clang\ClangConfig.cmake'))) { return $tree }
    }
    Write-Host 'No Clang/LLVM development tree: unpack clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz under C:\LLVM, or set CT_CLANG_INSTALL_DIR.'
    exit 1
}

function Build-Core {
    Enter-Msvc
    $tree = Find-ClangTree
    # Release with the /MD runtime, as the prebuilt Clang libraries are: a /MDd object fails to link with LNK2038.
    # The compile database for every folder, not only src/: clang-tidy -p build reads the tests from it too.
    cmake -S . -B build -G Ninja '-DCMAKE_CXX_COMPILER=cl' '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL' '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON' "-DCT_Clang_INSTALL_DIR=$tree"
    if ($LASTEXITCODE -ne 0) { exit 1 }
    cmake --build build
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

function Assert-NoWordInCore([string]$What, [string]$Words) {
    # A folder with no tracked file would make the search below find nothing and read as a pass.
    foreach ($folder in $Provides) {
        if (-not (git ls-files -- $folder)) { Write-Host "$folder holds no tracked file, so the $What check would prove nothing."; exit 1 }
    }
    git grep -n -I -w -E --untracked $Words -- @Provides
    # 1 is the verdict wanted: found nothing. 0 is a hit, and anything else is a search that did not run.
    if ($LASTEXITCODE -ne 1) { Write-Host "The $What check failed: exit $LASTEXITCODE, over $($Provides -join ', ')."; exit 1 }
    Write-Host "No $What in $($Provides -join ', ')."
}

Push-Location $root
try {
    switch ($Verb) {
        'build' {
            Build-Core
            exit 0
        }
        'install' { Write-Host 'nothing to install'; exit 0 }
        'uninstall' { Write-Host 'nothing to uninstall'; exit 0 }
        'clean' {
            foreach ($path in 'dist', 'build', 'out') {
                if (Test-Path $path) { Remove-Item -Recurse -Force $path }
            }
            exit 0
        }
        'run' {
            # The tool rewrites the files it is given in place: run <file.cpp> --
            Build-Core
            & (Join-Path $root 'build\refactor_tool.exe') @RunArgs
            exit $LASTEXITCODE
        }
        'publish' {
            # Hands the sources to the lab: the tree section 6 fixes for a $Needs entry.
            if (-not $env:LAB_SHARE) { Write-Host 'LAB_SHARE is not set, so there is nowhere to publish to'; exit 1 }
            $target = Join-Path $env:LAB_SHARE "needs\$Name\v$Version"
            foreach ($folder in $Provides) {
                $destination = Join-Path $target $folder
                New-Item -ItemType Directory -Force $destination | Out-Null
                Copy-Item -Recurse -Force "$folder\*" $destination
            }
            exit 0
        }
        'info' {
            Write-Host "Name    : $Name"
            Write-Host "Code    : $Code"
            Write-Host "Version : $Version"
            Write-Host "Summary : $Summary"
            Write-Host "Provides: $($Provides -join ', ')"
            exit 0
        }
        'test' {
            # The git hooks first (section 10), so a fresh clone has them too.
            git -C $root config core.hooksPath .claude/hooks/git
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Build-Core
            # --no-tests=error: ctest alone says "No tests were found" and exits 0.
            ctest --test-dir build --output-on-failure --no-tests=error
            if ($LASTEXITCODE -ne 0) { exit 1 }
            # -p build after the build. The header comes in through the tool's unit and .clang-tidy's filter.
            clang-tidy -p build --quiet (git ls-files ':(glob)src/*.cpp' ':(glob)tests/*.cpp')
            if ($LASTEXITCODE -ne 0) { exit 1 }
            # In place, never --dry-run: the gate runs git diff --exit-code after this verb. :(glob) keeps * inside one folder, so tests/tests_data, the tool's input, stays as it is.
            clang-format -i (git ls-files ':(glob)include/*.h' ':(glob)src/*.cpp' ':(glob)tests/*.cpp')
            if ($LASTEXITCODE -ne 0) { exit 1 }
            Assert-NoWordInCore 'lock' 'mutex|timed_mutex|recursive_mutex|recursive_timed_mutex|shared_mutex|shared_timed_mutex|lock_guard|unique_lock|shared_lock|scoped_lock|condition_variable|condition_variable_any|counting_semaphore|binary_semaphore|latch|barrier|call_once|once_flag|CRITICAL_SECTION|pthread_mutex_t|pthread_rwlock_t|pthread_spinlock_t'
            Assert-NoWordInCore 'exception' 'throw|try|catch'
            exit 0
        }
    }
}
finally {
    Pop-Location
}
