# The corridor sweep on Windows: one run of the game, scripted and recorded, its frames
# dumped and checked. See README.md beside this.
#
#   tests\sweep\run_corridor.ps1 -Out <folder> -Game <pristine game folder> [-Settings <conf>]
#                                [-Exe <timeslip.exe>] [-Replay <trace>]
#
# -Settings: a settings file to play with (copy your own and set fullscreen = 0; the
# run never touches your real one). -Replay replays a recording made by an earlier
# run (<Out>\corridor.trace) instead of recording a new one, to compare settings
# that only change the picture.
param(
    [Parameter(Mandatory)][string]$Out,
    [Parameter(Mandatory)][string]$Game,
    [string]$Settings = "",
    [string]$Exe = "",
    [string]$Replay = ""
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repo = Split-Path (Split-Path $here -Parent) -Parent
if (-not $Exe) { $Exe = Join-Path $repo "build\Release\timeslip.exe" }
if (-not (Test-Path $Exe)) { throw "No game at ${Exe}: build it first (ninja timeslip)" }
# -Out is emptied first, so only a folder that is empty or an earlier run's (it has
# the marker this writes) is taken.
if (Test-Path $Out) {
    if ((Get-ChildItem -Force $Out | Measure-Object).Count -gt 0 -and -not (Test-Path "$Out\.corridor-run")) {
        throw "$Out has other things in it: give a new or empty folder" }
    Remove-Item -Recurse -Force $Out
}
New-Item -ItemType Directory -Force "$Out\saves", "$Out\game\UDATA" | Out-Null
Set-Content -Encoding ascii "$Out\.corridor-run" "a corridor sweep run (tests\sweep\run_corridor.ps1)"
# The game linked, not copied: the run only reads its disc's files.
Get-ChildItem $Game -Recurse | Where-Object { $_.FullName -notmatch '\\UDATA(\\|$)' } | ForEach-Object {
    $rel = $_.FullName.Substring($Game.Length).TrimStart('\'); $to = Join-Path "$Out\game" $rel
    if ($_.PSIsContainer) { New-Item -ItemType Directory -Force $to | Out-Null }
    else { New-Item -ItemType HardLink -Path $to -Target $_.FullName | Out-Null } }
$script = Get-Content "$here\corridor.sweep" | Where-Object { $_ -notmatch '^\s*#' }
($script + "log $Out\sweep.csv") | Set-Content -Encoding ascii "$Out\corridor.sweep"

$env:RECOMP_GAME_DIR = "$Out\game"; $env:RECOMP_SAVE_DIR = "$Out\saves"
$env:RECOMP_MUTE = "1"; $env:RECOMP_WINDOW_BACKGROUND = "1"; $env:RECOMP_WINDOW_SIZE = "1600x900"
if ($Settings) { $env:RECOMP_DISPLAY_CONFIG = $Settings }
$env:RECOMP_TS2_SWEEP = "$Out\corridor.sweep"
$env:RECOMP_LOCKSTEP_END = "7320"
if ($Replay) {
    $env:RECOMP_LOCKSTEP_REPLAY = $Replay
    Remove-Item Env:RECOMP_LOCKSTEP, Env:RECOMP_INPUT_SEQ -ErrorAction SilentlyContinue
} else {
    $env:RECOMP_LOCKSTEP = "1"; $env:RECOMP_LOCKSTEP_TRACE = "$Out\corridor.trace"
    $env:RECOMP_INPUT_SEQ = (Get-Content "$here\corridor.seq" -Raw).Trim()
}
$env:RECOMP_PRESENT_DUMP = "$Out\p_"
$env:RECOMP_PRESENT_DUMP_TICKS = (Get-Content "$here\corridor.ticks" -Raw).Trim()
$env:RECOMP_PRESENT_DUMP_FRAMES = "3"; $env:RECOMP_PRESENT_DUMP_MAX = "6000"
# Through cmd's own redirection: a piped stderr stalls the game (see tools\ in the repo's notes).
$cmd = Start-Process -FilePath cmd.exe -WorkingDirectory (Split-Path $Exe) -PassThru -WindowStyle Hidden `
    -ArgumentList "/c `"`"$Exe`" 2>`"$Out\run.log`"`""
# The run ends itself at RECOMP_LOCKSTEP_END (about two minutes of play and the menus
# before it); twenty minutes is a hang.
if (-not $cmd.WaitForExit(1200000)) {
    Get-Process timeslip -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Resolve-Path $Exe).Path } |
        Stop-Process -Force
    Write-Warning "the run did not end by itself in 20 minutes; stopped"
}
Select-String -Path "$Out\run.log" -Pattern "LOCKSTEP\].*(same|differ|recorded)" | Select-Object -Last 1 | ForEach-Object { $_.Line }
py -3 "$here\analyze.py" $Out --jpg
py -3 "$here\odd.py" $Out
Remove-Item -Recurse -Force "$Out\game" -ErrorAction SilentlyContinue
