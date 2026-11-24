<#
Installs the built Timeslip on this PC the way a Windows program is installed: into
%LOCALAPPDATA%\Programs\Timeslip, with a Start menu and a desktop shortcut to its
launcher, and an entry in Settings > Apps that removes it again.

    tools\install_windows.ps1 [-Game <folder>] [-Dest <folder>] [-NoArt] [-Uninstall]

-Game is the game's folder (default.xbe beside data\, music\, and the saves in UDATA):
the install links to it rather than copying it, so saves and settings carry on where
they were. The launcher's art is made from it once (tools\make_disc_art.py) if it is not
there yet. Nothing of the game is copied anywhere.
#>
param(
    [string]$Game = "",
    [string]$Dest = "$env:LOCALAPPDATA\Programs\Timeslip",
    [switch]$NoArt,
    [switch]$Uninstall
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$build = Join-Path $repo "build\Release"
if (-not $Game) { $Game = Join-Path $repo "game" }
$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "Timeslip.lnk"
$desktop = Join-Path ([Environment]::GetFolderPath("Desktop")) "Timeslip.lnk"
$uninstKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Timeslip"

function Stop-Running {
    Get-Process timeslip, timeslip_launcher -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($Dest, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.Id -Force; Start-Sleep -Milliseconds 300 }
}

if ($Uninstall) {
    Stop-Running
    foreach ($l in $startMenu, $desktop) { if (Test-Path $l) { Remove-Item $l -Force } }
    if (Test-Path $Dest) {
        $j = Join-Path $Dest "game"
        if (Test-Path $j) { (Get-Item $j).Delete() }      # the link only, never the game
        Remove-Item -Recurse -Force $Dest
    }
    if (Test-Path $uninstKey) { Remove-Item $uninstKey -Force }
    "Timeslip removed. The game's folder, saves and settings are untouched."
    return
}

foreach ($f in "timeslip.exe", "timeslip_launcher.exe") {
    if (-not (Test-Path (Join-Path $build $f))) { throw "$f is not built: scripts\build.py first" }
}
if (-not (Test-Path (Join-Path $Game "default.xbe"))) { throw "no game at $Game (default.xbe)" }

Stop-Running
New-Item -ItemType Directory -Force $Dest | Out-Null
foreach ($f in "timeslip.exe", "timeslip_launcher.exe") { Copy-Item (Join-Path $build $f) $Dest -Force }
# Vulkan's shader compiler beside the game (rhi_vulkan_dxc.cpp loads it from there first).
$dxc = Join-Path $repo "recompose\third_party\dxc\bin\x64"
foreach ($f in "dxcompiler.dll", "dxil.dll") { if (Test-Path (Join-Path $dxc $f)) { Copy-Item (Join-Path $dxc $f) $Dest -Force } }
Copy-Item (Join-Path $repo "LICENSE") $Dest -Force -ErrorAction SilentlyContinue
Copy-Item $PSCommandPath (Join-Path $Dest "uninstall.ps1") -Force     # what Settings > Apps runs
Copy-Item (Join-Path $repo "art\icon-256.png") (Join-Path $Dest "icon.png") -Force -ErrorAction SilentlyContinue

# The game: a link to its folder, found where the game and the launcher look first.
$link = Join-Path $Dest "game"
if (Test-Path $link) { (Get-Item $link).Delete() }
New-Item -ItemType Junction -Path $link -Target (Resolve-Path $Game).Path | Out-Null

# The launcher's art, from this copy of the game, once.
$art = Join-Path $env:LOCALAPPDATA "xboxrecomp\art\4553000A"
if (-not $NoArt -and -not (Test-Path (Join-Path $art "backdrop.jpg")) -and -not (Test-Path (Join-Path $art "backdrop.png"))) {
    $py = (Get-Command py -ErrorAction SilentlyContinue).Source
    if (-not $py) { $py = (Get-Command python -ErrorAction SilentlyContinue).Source }
    if ($py) {
        "Making the launcher's art from your game (about three minutes)..."
        & $py (Join-Path $repo "tools\make_disc_art.py") --game $Game --out $art --build $build
    } else { "No Python here: the launcher writes the game's name until tools\make_disc_art.py is run." }
}

# Shortcuts, with the launcher's own icon.
$shell = New-Object -ComObject WScript.Shell
foreach ($l in $startMenu, $desktop) {
    $s = $shell.CreateShortcut($l)
    $s.TargetPath = Join-Path $Dest "timeslip_launcher.exe"
    $s.WorkingDirectory = $Dest
    $s.IconLocation = (Join-Path $Dest "timeslip_launcher.exe") + ",0"
    $s.Description = "TimeSplitters 2, recompiled to run natively"
    $s.Save()
}

# Settings > Apps.
$ver = (git -C $repo rev-parse --short HEAD 2>$null)
New-Item -Path $uninstKey -Force | Out-Null
$props = @{
    DisplayName = "Timeslip"; DisplayVersion = "$ver"; Publisher = "Timeslip";
    InstallLocation = $Dest; DisplayIcon = (Join-Path $Dest "timeslip_launcher.exe");
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Dest 'uninstall.ps1')`" -Uninstall -Dest `"$Dest`"";
    NoModify = 1; NoRepair = 1
}
foreach ($k in $props.Keys) {
    $type = if ($props[$k] -is [int]) { "DWord" } else { "String" }
    New-ItemProperty -Path $uninstKey -Name $k -Value $props[$k] -PropertyType $type -Force | Out-Null
}
"Timeslip $ver installed in $Dest"
"  game:      $link -> $Game"
"  shortcuts: Start menu and desktop"
