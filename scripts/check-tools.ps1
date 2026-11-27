# Checks for what building Leonida X needs: the Visual Studio C++ build tools and
# Rust (rustup). Offers to install what is missing with winget, after asking. Run by
# start-measure.cmd; exits 1 when something is still missing.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\check-tools.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Test-BuildTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    [bool]$path
}

function Find-Rustup {
    $cmd = Get-Command rustup -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Installed in this session: the window's PATH doesn't have it yet.
    $own = Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'
    if (Test-Path -LiteralPath $own) { return $own }
    $null
}

function Install-WithWinget([string]$id, [string[]]$extra) {
    & winget install --id $id --exact --accept-package-agreements --accept-source-agreements @extra
    # winget returns a non-zero code when the package is already there; the checks after decide.
}

$needTools = -not (Test-BuildTools)
$needRust = -not (Find-Rustup)
if (-not $needTools -and -not $needRust) {
    Write-Host 'Build tools: found. Rust: found.'
} else {
    Write-Host ''
    Write-Host 'Building Leonida X needs these, and this PC is missing:'
    if ($needTools) { Write-Host '  - Visual Studio 2022 Build Tools with C++ (about 3 GB, 5 to 15 minutes; Windows asks for admin rights)' }
    if ($needRust) { Write-Host '  - Rust, through rustup (about 300 MB, a few minutes)' }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host ''
        Write-Host 'winget is not on this PC, so they have to be installed by hand:'
        if ($needTools) { Write-Host '  https://visualstudio.microsoft.com/visual-cpp-build-tools/  (pick "Desktop development with C++")' }
        if ($needRust) { Write-Host '  https://rustup.rs/' }
        Write-Host 'Then start this again.'
        exit 1
    }
    $answer = Read-Host 'Install them now with winget? [Y/n]'
    if ($answer.Trim() -notmatch '^(y|yes)?$') {
        Write-Host 'Nothing installed. Install them yourself and start this again.'
        exit 1
    }
    # The build tools first: rustup's installer looks for them.
    if ($needTools) {
        Install-WithWinget 'Microsoft.VisualStudio.2022.BuildTools' @(
            '--override', '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
        if (-not (Test-BuildTools)) {
            Write-Host 'The C++ build tools are still missing. Install them from'
            Write-Host 'https://visualstudio.microsoft.com/visual-cpp-build-tools/ and start this again.'
            exit 1
        }
    }
    if ($needRust) {
        Install-WithWinget 'Rustlang.Rustup' @()
        if (-not (Find-Rustup)) {
            Write-Host 'Rust is still missing. Install it from https://rustup.rs/ and start this again.'
            exit 1
        }
    }
}

# The Rust version rust-toolchain.toml pins; rustup installs it once and keeps it.
$rustup = Find-Rustup
Push-Location $root
try {
    & $rustup toolchain install
    if ($LASTEXITCODE -ne 0) { Write-Warning "rustup could not install the pinned Rust version (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}
