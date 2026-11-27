# After a measure-gta6.ps1 run: asks whether to make a short test report, shows all of it,
# and if the player agrees, copies it to the clipboard and opens the test-results channel
# of the project's Discord, where they post it themselves. Nothing is sent from here.
# The report holds figures only (the card, its driver, the CPU, frame rates), never the log
# itself: logs can quote game data (docs/asset-policy.md). Reports are kept in
# %LOCALAPPDATA%\leonida\reports.
#
#   powershell -ExecutionPolicy Bypass -File .\scripts\test-report.ps1 -Log <a measure-*.log>

param(
    [Parameter(Mandatory = $true)]
    [string]$Log,
    # The LEONIDA_* switches the run had on, as NAME=value.
    [string[]]$SpeedSwitches = @(),
    [ValidateSet('on', 'off')]
    [string]$SwitchMode = 'on',
    [string]$WarmUp = 'not asked',
    # When the run started; a crashes.log written since then means it crashed. The log's own
    # creation time when not given.
    [datetime]$Started = [datetime]::MinValue,
    [string]$ExitCode = '',
    # leonida.exe, to find the data folder (crashes.log) with `leonida config`.
    [string]$Exe = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'leonida-settings.ps1')

$server = '1574773017114841229'
$channel = '1575267731857739916'
$invite = 'https://discord.gg/dxMD2XqyEJ'
$inv = [cultureinfo]::InvariantCulture

function Format-Num([double]$v, [int]$digits) { $v.ToString("F$digits", $inv) }

function Limit-Text([string]$s, [int]$n) {
    if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s }
}

# The driver of the card named $name, in the vendor's own numbering where it has one.
function Get-DriverVersion([string]$name) {
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($key in @(Get-ChildItem -LiteralPath $class -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^\d{4}$') { continue }
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or [string]$p.DriverDesc -ne $name) { continue }
        $v = [string]$p.DriverVersion
        # NVIDIA's number is the last five digits of the Windows one: 32.0.16.2124 is 621.24.
        if ([string]$p.MatchingDeviceId -match 'ven_10de' -and $v -match '(\d)\.(\d{4})$') {
            $d = $Matches[1] + $Matches[2]
            return '{0}.{1} ({2})' -f $d.Substring(0, 3), $d.Substring(3), $v
        }
        if ($p.RadeonSoftwareVersion) { return 'Adrenalin {0} ({1})' -f $p.RadeonSoftwareVersion, $v }
        return $v
    }
    'unknown'
}

function Get-LeonidaVersion {
    try {
        $commit = & git -C $root rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $commit) { return 'unknown (not a git checkout)' }
        $changed = & git -C $root status --porcelain --untracked-files=no 2>$null
        if ($changed) { "$commit with local changes" } else { "$commit" }
    } catch {
        'unknown (git not found)'
    }
}

# The frame log's "frame times" lines (crates/leonida-gpu/src/framelog.rs): the seconds each
# reading covers and every frame's length in ms.
function Read-FrameReadings([string]$path) {
    $readings = @()
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        $plain = $line -replace '\x1b\[[0-9;]*m', ''
        if ($plain -match 'frame times: \d+ frames in ([\d.]+) s: .*; each: ([\d ]+?)\s*$') {
            $readings += [pscustomobject]@{
                Seconds = [double]$Matches[1]
                Frames = @($Matches[2] -split ' ' | Where-Object { $_ } | ForEach-Object { [double]$_ })
            }
        }
    }
    $readings
}

# The readings from the last one back until they cover $want seconds (all of them for 0).
function Get-FrameSummary($readings, [double]$want) {
    $seconds = 0.0
    $frames = @()
    for ($i = $readings.Count - 1; $i -ge 0; $i--) {
        $seconds += $readings[$i].Seconds
        $frames += $readings[$i].Frames
        if ($want -gt 0 -and $seconds -ge $want) { break }
    }
    if ($frames.Count -eq 0 -or $seconds -le 0) { return $null }
    $sorted = @($frames | Sort-Object)
    [pscustomobject]@{
        Seconds = $seconds
        Count = $frames.Count
        Fps = $frames.Count / $seconds
        MedianMs = $sorted[[int][math]::Floor(($sorted.Count - 1) / 2)]
        LongestMs = $sorted[-1]
    }
}

function Format-Summary($s, [string]$what) {
    '{0} FPS average over {1} ({2} frames in {3} s); median frame {4} ms, longest {5} ms' -f `
        (Format-Num $s.Fps 1), $what, $s.Count, (Format-Num $s.Seconds 1), (Format-Num $s.MedianMs 0), (Format-Num $s.LongestMs 0)
}

# Whether a crash report was written since $since; only that, never what is in it.
function Test-CrashWritten([string]$exe, [datetime]$since) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return 'unknown' }
    # leonida.toml is read from the current folder.
    Push-Location $root
    try { $out = & $exe config } finally { Pop-Location }
    $line = $out | Where-Object { $_ -match '^data_dir\s*:' } | Select-Object -First 1
    if ($line -notmatch '^data_dir\s*:\s*(.+?)\s*$') { return 'unknown' }
    $dir = $Matches[1]
    if (-not (Test-Path -LiteralPath $dir)) { return 'no' }
    $new = @(Get-ChildItem -LiteralPath $dir -Filter 'crashes.log' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since })
    if ($new.Count -gt 0) { 'yes' } else { 'no' }
}

Write-Host ''
Write-Host '=== Test report ==='
Write-Host 'A short report from this run helps make Leonida X better: it shows which speed'
Write-Host 'switches help on which graphics card (gpu-profiles.json) and where the game crashes.'
Write-Host ''
Write-Host 'It holds only:'
Write-Host '  - your graphics card, its memory and driver; your CPU, RAM and Windows version'
Write-Host '  - the Leonida X version, the speed switches that were on, and the shader warm-up'
Write-Host '  - frame rates from this run, and whether a crash report was written'
Write-Host '  - what you type in next, if anything'
Write-Host 'It never holds your name, user name, folder paths, log files, game files or screenshots.'
Write-Host ''
Write-Host 'This script sends nothing. If you agree to share, it copies the report and opens the'
Write-Host '#test-results channel in Discord; you read it there and decide whether to post it.'
$answer = Read-Host 'Make a report? [Y/n]'
if ($answer.Trim() -notmatch '^(y|yes)?$') {
    Write-Host 'No report made.'
    return
}

Write-Host ''
Write-Host 'Two optional questions (press Enter to skip). Do not paste log lines or file paths.'
$where = Limit-Text (Read-Host 'Where in the game were you at the end (for example: opening cutscene, first room)?').Trim() 300
$issue = Limit-Text (Read-Host 'Anything wrong (crash, missing textures, flashing, sound)?').Trim() 600

if ($Started -eq [datetime]::MinValue) { $Started = (Get-Item -LiteralPath $Log).CreationTime }
$gpu = Get-LeonidaGpu
$cpu = ([string]@(Get-CimInstance Win32_Processor)[0].Name).Trim()
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$os = (Get-CimInstance Win32_OperatingSystem).Caption -replace '^Microsoft\s+', ''
$nt = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$names = @($SpeedSwitches | Where-Object { $_ } | ForEach-Object {
    $name, $value = $_ -split '=', 2
    $short = $name -replace '^LEONIDA_', ''
    if ($value -eq '1') { $short } else { "$short=$value" }
})
$switchText = $SwitchMode
if ($names.Count -gt 0) { $switchText += ': ' + ($names -join ', ') }

$readings = @(Read-FrameReadings $Log)
$last = Get-FrameSummary $readings 60
$all = Get-FrameSummary $readings 0
$crashed = Test-CrashWritten $Exe $Started

$lines = @(
    '**Leonida X test report**'
    "GPU: $($gpu.Name), $($gpu.VramMB) MB"
    "Driver: $(Get-DriverVersion $gpu.Name)"
    "CPU: $cpu"
    "RAM: $ram GB"
    ('Windows: {0} {1}, build {2}.{3}' -f $os, $nt.DisplayVersion, $nt.CurrentBuild, $nt.UBR)
    "Build: Leonida X $(Get-LeonidaVersion)"
    "Speed switches: $switchText"
    "Shader warm-up: $WarmUp"
)
if ($where) { $lines += "Where: $where" }
if (-not $all) {
    $lines += 'Performance: no frame times in the log (the game closed before its first frames?)'
} elseif ($all.Seconds -le $last.Seconds) {
    $lines += 'Performance: ' + (Format-Summary $all 'the whole run')
} else {
    $lines += 'Performance: ' + (Format-Summary $last 'the last minute before the game closed')
    $lines += 'Whole run: ' + (Format-Summary $all 'the whole run, menus and loading included')
}
$end = "Crash report written: $crashed"
if ($ExitCode -ne '') { $end += " (exit code $ExitCode)" }
$lines += $end
$lines += 'Issue: ' + $(if ($issue) { $issue } else { 'none noticed' })
$text = $lines -join "`r`n"

$dir = Join-Path $env:LOCALAPPDATA 'leonida\reports'
New-Item -ItemType Directory -Force $dir | Out-Null
$file = Join-Path $dir ('report-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date))
Set-Content -LiteralPath $file -Value $text -Encoding UTF8

Write-Host ''
Write-Host '----- the report, exactly as it would be shared -----'
Write-Host $text
Write-Host '-----------------------------------------------------'
Write-Host "Saved to $file"
$answer = Read-Host 'Copy it and open #test-results in Discord to post it? [Y/n]'
if ($answer.Trim() -notmatch '^(y|yes)?$') {
    Write-Host 'Not shared. The report stays in the file above.'
    return
}
Set-Clipboard -Value $text
$url = if (Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\discord') {
    "discord://-/channels/$server/$channel"
} else {
    "https://discord.com/channels/$server/$channel"
}
Start-Process $url
Write-Host 'Copied. In Discord, click the message box in #test-results, press Ctrl+V, read it, then Enter.'
Write-Host "Not on the server yet? Join first: $invite"
Write-Host 'Attach no log files: they can quote game data.'
