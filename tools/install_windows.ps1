<#
Installs a built game of the Timeslip collection on this PC the way a Windows program is
installed: into %LOCALAPPDATA%\Programs\<its folder>, with a Start menu and a desktop
shortcut to its launcher, and an entry in Settings > Apps that removes it again.

    tools\install_windows.ps1 [-Title ts2|fp] [-Game <folder>] [-Dest <folder>] [-NoArt] [-NoShortcuts] [-KeepLauncher] [-Uninstall]

-Title is the game: ts2, TimeSplitters 2 (the default; "Timeslip", built in build\Release),
or fp, TimeSplitters: Future Perfect ("TimeSplitters Future Perfect", built in
fp\build\Release by tools\build_windows.ps1 -Title fp). Each has its own folder, shortcuts
and Settings > Apps entry.

-Game is the game's folder (default.xbe beside its data, and the saves in UDATA): the
install links to it rather than copying it, so saves and settings carry on where they
were. The launcher's art is made from it once (tools\make_disc_art.py) if it is not there
yet. Nothing of the game is copied anywhere.

The install has an updater beside the launcher (update.ps1, which runs this checkout's
tools\update_windows.ps1): the launcher's Updates tile offers the newest GitHub release
and installs it. -KeepLauncher is how the updater reinstalls: the launcher that started it
keeps running, and its file is swapped by renaming the old one aside. -NoShortcuts leaves
the Start menu, the desktop and Settings > Apps alone (a test install beside the real one).
-Uninstall removes the install, and only the shortcuts and the Settings > Apps entry that
point into it.
#>
param(
    [ValidateSet("ts2", "fp")][string]$Title = "ts2",
    [string]$Game = "",
    [string]$Dest = "",
    [switch]$NoArt,
    [switch]$NoShortcuts,
    [switch]$KeepLauncher,
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

# Each game: its executables, where it is built, its name on this PC and its art's title id.
$titles = @{
    ts2 = @{ Exe = "timeslip"; Build = "build\Release"; Game = "game"; Folder = "Timeslip";
             Name = "Timeslip"; Link = "Timeslip"; Key = "Timeslip"; ArtId = "4553000A";
             Desc = "TimeSplitters 2, recompiled to run natively"; Icon = "timeslip.ico" }
    fp  = @{ Exe = "timeslip_fp"; Build = "fp\build\Release"; Game = "fp\game"; Folder = "Timeslip Future Perfect";
             Name = "TimeSplitters Future Perfect"; Link = "TimeSplitters Future Perfect"; Key = "TimeslipFuturePerfect";
             ArtId = "45410066"; Desc = "TimeSplitters: Future Perfect, recompiled to run natively";
             Icon = "timeslip_fp.ico" }
}
$t = $titles[$Title]
$exe = "$($t.Exe).exe"
$launcher = "$($t.Exe)_launcher.exe"
$build = Join-Path $repo $t.Build
if (-not $Game) { $Game = Join-Path $repo $t.Game }
if (-not $Dest) { $Dest = Join-Path $env:LOCALAPPDATA "Programs\$($t.Folder)" }
$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "$($t.Link).lnk"
$desktop = Join-Path ([Environment]::GetFolderPath("Desktop")) "$($t.Link).lnk"
$uninstKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($t.Key)"

function Stop-Running {
    $names = if ($KeepLauncher) { @($t.Exe) } else { @($t.Exe, "$($t.Exe)_launcher") }
    Get-Process $names -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($Dest, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.Id -Force; Start-Sleep -Milliseconds 300 }
}

# Whether a path is inside this install (a shortcut's target, the Apps entry's location).
function In-Dest([string]$path) {
    if (-not $path) { return $false }
    $d = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
    $p = [IO.Path]::GetFullPath($path).TrimEnd('\')
    return $p.Equals($d, [StringComparison]::OrdinalIgnoreCase) -or
           $p.StartsWith($d + '\', [StringComparison]::OrdinalIgnoreCase)
}

# Copy a program into the install. One that is running (the launcher that started an
# update) cannot be written, but can be renamed: it goes aside as <name>.old.exe, which
# the next install deletes.
function Install-File([string]$from, [string]$to) {
    $old = [IO.Path]::ChangeExtension($to, ".old.exe")
    if (Test-Path $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue }
    try { Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop }
    catch {
        if (-not (Test-Path $to)) { throw }
        if (Test-Path $old) { throw "$to is in use and $old cannot be removed" }
        Rename-Item -LiteralPath $to -NewName (Split-Path $old -Leaf) -ErrorAction Stop
        Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
    }
}

if ($Uninstall) {
    Stop-Running
    # Only what belongs to this install: a test install's uninstall leaves the real
    # one's shortcuts and Apps entry alone.
    $shell = New-Object -ComObject WScript.Shell
    foreach ($l in $startMenu, $desktop) {
        if ((Test-Path $l) -and (In-Dest $shell.CreateShortcut($l).TargetPath)) { Remove-Item $l -Force }
    }
    if (Test-Path $Dest) {
        $j = Join-Path $Dest "game"
        if (Test-Path $j) { (Get-Item $j).Delete() }      # the link only, never the game
        Remove-Item -Recurse -Force $Dest
    }
    if ((Test-Path $uninstKey) -and (In-Dest (Get-ItemProperty $uninstKey).InstallLocation)) {
        Remove-Item $uninstKey -Force
    }
    "$($t.Name) removed. The game's folder, saves and settings are untouched."
    return
}

$builder = if ($Title -eq "ts2") { "scripts\build.py" } else { "tools\build_windows.ps1 -Title $Title" }
foreach ($f in $exe, $launcher) {
    if (-not (Test-Path (Join-Path $build $f))) { throw "$f is not built: $builder first" }
}
if (-not (Test-Path (Join-Path $Game "default.xbe"))) { throw "no game at $Game (default.xbe)" }

Stop-Running
New-Item -ItemType Directory -Force $Dest | Out-Null
foreach ($f in $exe, $launcher) { Install-File (Join-Path $build $f) (Join-Path $Dest $f) }
# Vulkan's shader compiler beside the game (rhi_vulkan_dxc.cpp loads it from there first).
$dxc = Join-Path $repo "recompose\third_party\dxc\bin\x64"
foreach ($f in "dxcompiler.dll", "dxil.dll") { if (Test-Path (Join-Path $dxc $f)) { Copy-Item (Join-Path $dxc $f) $Dest -Force } }
# FFmpeg's libraries beside a game that plays its movies through them (Future Perfect's
# XMV): the three the movie player loads (recompose src/video/xmv_decode.c), which look
# beside the game first.
$ffbin = Join-Path $repo "recompose\third_party\ffmpeg\bin"
if ($Title -eq "fp" -and (Test-Path $ffbin)) {
    Get-ChildItem $ffbin -Filter *.dll | Where-Object { $_.Name -match '^(avcodec|avutil|swresample)-\d+\.dll$' } |
        ForEach-Object { Copy-Item $_.FullName $Dest -Force }
}
Copy-Item (Join-Path $repo "LICENSE") $Dest -Force -ErrorAction SilentlyContinue
Copy-Item $PSCommandPath (Join-Path $Dest "uninstall.ps1") -Force     # what Settings > Apps runs
if ($Title -eq "ts2") {
    Copy-Item (Join-Path $repo "art\icon-256.png") (Join-Path $Dest "icon.png") -Force -ErrorAction SilentlyContinue
}

# The updater the launcher's Updates tile runs: this checkout's, for this install.
$upd = @(
    "# Written by tools\install_windows.ps1: the launcher's Updates tile runs this.",
    "& '$((Join-Path $repo 'tools\update_windows.ps1') -replace "'", "''")' -Title $Title -Dest '$($Dest -replace "'", "''")'$(if ($NoShortcuts) { ' -NoShortcuts' }) @args",
    "exit `$LASTEXITCODE"
)
Set-Content -LiteralPath (Join-Path $Dest "update.ps1") -Value $upd -Encoding ASCII

# The game: a link to its folder, found where the game and the launcher look first.
$link = Join-Path $Dest "game"
if (Test-Path $link) { (Get-Item $link).Delete() }
New-Item -ItemType Junction -Path $link -Target (Resolve-Path $Game).Path | Out-Null

# The launcher's art, from this copy of the game, once.
$art = Join-Path $env:LOCALAPPDATA "xboxrecomp\art\$($t.ArtId)"
$py = (Get-Command py -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue).Source }
if (-not $NoArt -and -not (Test-Path (Join-Path $art "backdrop.jpg")) -and -not (Test-Path (Join-Path $art "backdrop.png"))) {
    if ($py) {
        "Making the launcher's art from your game (a few minutes)..."
        & $py (Join-Path $repo "tools\make_disc_art.py") --title $Title --game $Game --out $art --build $build
    } else { "No Python here: the launcher writes the game's name until tools\make_disc_art.py is run." }
}

# The icon, from this copy of the game (tools\make_icon.py): the title screen's
# own logo, sharp, from the launcher's art above (the Xbox dashboard picture,
# 128 pixels, at 48 and below, and alone when there is no art), or the
# launcher's own when there is no Python or game.
$icon = (Join-Path $Dest $launcher) + ",0"
if ($py -and (Test-Path (Join-Path $Game "default.xbe"))) {
    $ico = Join-Path $Dest $t.Icon
    & $py (Join-Path $repo "tools\make_icon.py") --game $Game --art $art --out $ico 2>&1 | Out-Null
    if (Test-Path $ico) { $icon = "$ico,0" }
}

if ($NoShortcuts) {
    "$($t.Name) $((git -C $repo rev-parse --short HEAD 2>$null)) installed in $Dest (no shortcuts)"
    return
}

# Shortcuts, with that icon.
$shell = New-Object -ComObject WScript.Shell
foreach ($l in $startMenu, $desktop) {
    $s = $shell.CreateShortcut($l)
    $s.TargetPath = Join-Path $Dest $launcher
    $s.WorkingDirectory = $Dest
    $s.IconLocation = $icon
    $s.Description = $t.Desc
    $s.Save()
}

# Settings > Apps.
$ver = (git -C $repo rev-parse --short HEAD 2>$null)
New-Item -Path $uninstKey -Force | Out-Null
$props = @{
    DisplayName = $t.Name; DisplayVersion = "$ver"; Publisher = "Timeslip";
    InstallLocation = $Dest; DisplayIcon = ($icon -replace ',0$', '');
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dest 'uninstall.ps1')`" -Title $Title -Uninstall -Dest `"$Dest`"";
    NoModify = 1; NoRepair = 1
}
foreach ($k in $props.Keys) {
    $type = if ($props[$k] -is [int]) { "DWord" } else { "String" }
    New-ItemProperty -Path $uninstKey -Name $k -Value $props[$k] -PropertyType $type -Force | Out-Null
}
"$($t.Name) $ver installed in $Dest"
"  game:      $link -> $Game"
"  shortcuts: Start menu and desktop"
