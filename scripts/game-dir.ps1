# Finding the folder of the player's copy of the game (the one with MicrosoftGame.config in
# it) for the run scripts: offers to look for it on this PC's drives, and otherwise asks for
# it, taking a folder or a file in it (the game's .exe dragged into the window). Dot-sourced:
#
#   . (Join-Path $PSScriptRoot 'scripts\game-dir.ps1')
#   $dir = Read-GameDir

# The game folder for what was typed or dragged in: that folder, the folder of a file in it,
# a folder up to three levels above, or its Content subfolder (where the Xbox app installs
# games). Empty when none of them has a MicrosoftGame.config.
function Resolve-GameDir([string]$text) {
    # Dragging a file in can type it as `& 'path'` or with double quotes around it.
    $path = ($text.Trim() -replace '^&\s*', '').Trim().Trim('"').Trim("'")
    if ($path -eq '') { return '' }
    try {
        if (-not (Test-Path -LiteralPath $path)) { return '' }
        $dir = (Resolve-Path -LiteralPath $path).ProviderPath
    } catch {
        return ''
    }
    if (Test-Path -LiteralPath $dir -PathType Leaf) { $dir = Split-Path -Parent $dir }
    $content = Join-Path $dir 'Content'
    if (Test-Path -LiteralPath (Join-Path $content 'MicrosoftGame.config') -PathType Leaf) { return $content }
    for ($i = 0; $i -lt 4 -and $dir; $i++) {
        if (Test-Path -LiteralPath (Join-Path $dir 'MicrosoftGame.config') -PathType Leaf) { return $dir }
        $dir = Split-Path -Parent $dir
    }
    ''
}

# The name a game folder's MicrosoftGame.config shows, or the folder's own name.
function Get-GameName([string]$dir) {
    try {
        $xml = [xml](Get-Content -LiteralPath (Join-Path $dir 'MicrosoftGame.config') -Raw)
        $name = [string]$xml.Game.ShellVisuals.DefaultDisplayName
        if ($name -and $name -notmatch '^ms-resource:') { return $name }
        $name = [string]$xml.Game.Identity.Name
        if ($name) { return $name }
    } catch { }
    $leaf = Split-Path -Leaf $dir
    if ($leaf -eq 'Content') { $leaf = Split-Path -Leaf (Split-Path -Parent $dir) }
    $leaf
}

# Folders with a MicrosoftGame.config on this PC's own drives: up to four levels under each
# drive's root (Windows' own folders skipped), and deeper in the user's Downloads, Desktop and
# Documents and the usual game libraries. Gives up after $seconds. Games named GTA first.
function Find-GameDirs([int]$seconds = 60) {
    $skip = 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'AppData', '$Recycle.Bin',
        'System Volume Information', 'Recovery', 'PerfLogs', '$WinREAgent', 'node_modules', '.git'
    # The deeper places go first: a folder is looked in once, at the depth it was first reached.
    $roots = @()
    foreach ($name in 'Downloads', 'Desktop', 'Documents') {
        $roots += , @((Join-Path $env:USERPROFILE $name), 3)
    }
    $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })
    foreach ($drive in $drives) {
        $r = $drive.RootDirectory.FullName
        foreach ($lib in 'Program Files\ModifiableWindowsApps', 'Program Files (x86)\Steam\steamapps\common',
            'Program Files\Epic Games') {
            $roots += , @((Join-Path $r $lib), 2)
        }
    }
    foreach ($drive in $drives) { $roots += , @($drive.RootDirectory.FullName, 4) }

    $found = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($root in $roots) {
        if (-not [System.IO.Directory]::Exists($root[0])) { continue }
        $queue = [System.Collections.Generic.Queue[object]]::new()
        $queue.Enqueue(@($root[0], 0))
        while ($queue.Count -gt 0) {
            if ($clock.Elapsed.TotalSeconds -ge $seconds) { break }
            $dir, $depth = $queue.Dequeue()
            if (-not $seen.Add($dir)) { continue }
            if ([System.IO.File]::Exists((Join-Path $dir 'MicrosoftGame.config'))) { $found.Add($dir); continue }
            if ($depth -ge $root[1]) { continue }
            try { $subs = [System.IO.Directory]::GetDirectories($dir) } catch { continue }
            foreach ($sub in $subs) {
                $info = [System.IO.DirectoryInfo]::new($sub)
                # Junctions such as "Documents and Settings" lead back into folders already seen.
                if ($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                if ($skip -contains $info.Name) { continue }
                $queue.Enqueue(@($sub, ($depth + 1)))
            }
        }
    }
    if ($clock.Elapsed.TotalSeconds -ge $seconds) { Write-Host "Stopped looking after $seconds s." }
    $games = @($found | ForEach-Object { [pscustomobject]@{ Dir = $_; Name = Get-GameName $_ } })
    $gtaFirst = @{ Expression = { if ("$($_.Name) $($_.Dir)" -match 'grand theft auto|gta') { 0 } else { 1 } } }
    @($games | Sort-Object $gtaFirst, Dir)
}

# Asks whether to look for the game folder, has the player confirm what was found, and
# otherwise asks for the folder until it has one. Returns the folder.
function Read-GameDir {
    Write-Host ''
    $answer = Read-Host 'Look for your copy of the game on this PC automatically? [Y/n]'
    if ($answer.Trim() -match '^(y|yes)?$') {
        Write-Host 'Looking on your drives (up to a minute)...'
        $games = @(Find-GameDirs)
        if ($games.Count -eq 1) {
            Write-Host ('Found: {0}' -f $games[0].Name)
            Write-Host ('  in {0}' -f $games[0].Dir)
            $answer = Read-Host 'Is this your copy of the game? [Y/n]'
            if ($answer.Trim() -match '^(y|yes)?$') { return $games[0].Dir }
        } elseif ($games.Count -gt 1) {
            Write-Host 'Found these games:'
            for ($i = 0; $i -lt $games.Count; $i++) {
                Write-Host ('  {0}. {1}' -f ($i + 1), $games[$i].Name)
                Write-Host ('     in {0}' -f $games[$i].Dir)
            }
            $answer = (Read-Host 'Type the number of your copy of the game, or press Enter to type its folder yourself').Trim()
            if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $games.Count) {
                return $games[[int]$answer - 1].Dir
            }
        } else {
            Write-Host 'No game folder found.'
        }
    }
    Write-Host ''
    Write-Host 'Tip: drag the game''s .exe (or its folder) from File Explorer into this window and press'
    Write-Host 'Enter, and the path is typed for you. Or click the address bar in File Explorer, copy it'
    Write-Host 'with Ctrl+C and paste it here with Ctrl+V or a right-click.'
    while ($true) {
        $dir = Resolve-GameDir (Read-Host 'Folder of your copy of the game (the one with MicrosoftGame.config in it)')
        if ($dir) { return $dir }
        Write-Host 'No MicrosoftGame.config there or in the folders around it, try again.'
    }
}
