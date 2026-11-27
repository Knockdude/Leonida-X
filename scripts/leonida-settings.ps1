# The LEONIDA_* switches for this PC's graphics card, from gpu-profiles.json (and
# gpu-profiles.local.json, if there is one). Dot-sourced by the run scripts:
#
#   . (Join-Path $PSScriptRoot 'scripts\leonida-settings.ps1')
#   Set-LeonidaProfiles $PSScriptRoot

# The card with the most memory of its own: name, vendor and memory in MB, from the
# display adapters' registry keys (Win32_VideoController stops counting at 4 GB).
function Get-LeonidaGpu {
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $best = $null
    foreach ($key in @(Get-ChildItem -LiteralPath $class -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^\d{4}$') { continue }
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or -not $p.DriverDesc) { continue }
        $bytes = [double]0
        $q = $p.'HardwareInformation.qwMemorySize'
        $d = $p.'HardwareInformation.MemorySize'
        if ($q) { $bytes = [double]$q }
        elseif ($d -is [byte[]] -and $d.Length -ge 4) { $bytes = [double][BitConverter]::ToUInt32($d, 0) }
        elseif ($d) { $bytes = [double]$d }
        $vendor = switch -Regex ([string]$p.MatchingDeviceId) {
            'ven_10de' { 'nvidia'; break }
            'ven_1002' { 'amd'; break }
            'ven_8086' { 'intel'; break }
            default { 'other' }
        }
        $gpu = [pscustomobject]@{ Name = [string]$p.DriverDesc; Vendor = $vendor; VramMB = [int]($bytes / 1MB) }
        if (-not $best -or $gpu.VramMB -gt $best.VramMB) { $best = $gpu }
    }
    if (-not $best) { $best = [pscustomobject]@{ Name = 'unknown'; Vendor = 'other'; VramMB = 0 } }
    $best
}

function Test-LeonidaMatch($match, $gpu) {
    if (-not $match) { return $true }
    if ($match.vendor -and $match.vendor -ne $gpu.Vendor) { return $false }
    if ($match.min_vram_mb -and $gpu.VramMB -lt [int]$match.min_vram_mb) { return $false }
    if ($match.max_vram_mb -and $gpu.VramMB -gt [int]$match.max_vram_mb) { return $false }
    if ($match.name -and $gpu.Name -notlike $match.name) { return $false }
    $true
}

# Sets the switches of the profiles that fit (or those LEONIDA_PROFILE names) and says
# which they were. -Gpu stands in for the card, for trying a profile out.
function Set-LeonidaProfiles([string]$Root, $Gpu = $null) {
    if (-not $Gpu) { $Gpu = Get-LeonidaGpu }
    $forced = @()
    if ($env:LEONIDA_PROFILE) { $forced = @($env:LEONIDA_PROFILE -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $set = [ordered]@{}
    $applied = @()
    # Switches an earlier run left in this window (this script, play.ps1, by hand) go, so the
    # profiles decide; LEONIDA_KEEP_WINDOW=1 keeps them. Paths, LEONIDA_PROFILE and LEONIDA_LOG stay.
    $stay = 'LEONIDA_CONFIG', 'LEONIDA_GAME_DIR', 'LEONIDA_CACHE_DIR', 'LEONIDA_DATA_DIR', 'LEONIDA_PROFILE', 'LEONIDA_LOG', 'LEONIDA_KEEP_WINDOW'
    if ($env:LEONIDA_KEEP_WINDOW -ne '1') {
        Get-ChildItem Env:LEONIDA_* | Where-Object { $_.Name -notin $stay } | ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }
    }
    $files = @(Join-Path $Root 'gpu-profiles.json')
    $local = Join-Path $Root 'gpu-profiles.local.json'
    if (Test-Path -LiteralPath $local) { $files += $local }
    foreach ($file in $files) {
        $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        foreach ($p in @($data.profiles)) {
            $wanted = if ($forced -contains 'none') { $false }
                elseif ($forced.Count -gt 0) { $p.name -eq 'base' -or $forced -contains $p.name }
                elseif ($p.opt_in) { $false }
                else { Test-LeonidaMatch $p.match $Gpu }
            if (-not $wanted) { continue }
            foreach ($s in @($p.env.PSObject.Properties)) { $set[$s.Name] = $s.Value }
            $applied += $p.name
        }
    }
    $kept = @()
    foreach ($name in $set.Keys) {
        if (Test-Path -LiteralPath "Env:$name") { $kept += $name; continue }
        if ($null -ne $set[$name]) { Set-Item -LiteralPath "Env:$name" ([string]$set[$name]) }
    }
    if ($applied.Count -eq 0) { $applied = @('none') }
    Write-Host ("graphics card: {0} ({1}, {2} MB); profiles: {3}" -f $Gpu.Name, $Gpu.Vendor, $Gpu.VramMB, ($applied -join ', '))
    if ($kept.Count -gt 0) { Write-Host ("already set in this window, left as they are: {0}" -f ($kept -join ', ')) }
}
