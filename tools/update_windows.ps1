<#
Timeslip's updater on Windows. The launcher's Updates tile runs it through update.ps1 beside
the launcher, which tools\install_windows.ps1 writes and which runs this file from the
checkout the install was built from.

    update_windows.ps1 -Dest <install> -Check   one line on standard output:
        available <tag> <commit>    a newer release is out
        current <tag> <commit>      the installed build is that release, or newer
        none                        no release has been published
        error <why>                 GitHub or git could not be asked
    update_windows.ps1 -Dest <install>          to the newest release: fetch it, lift and build
                                                again from the player's own disc, reinstall

-Title ts2|fp is the game the install holds (TimeSplitters 2 by default, or Future Perfect);
install_windows.ps1 writes it into update.ps1. The collection's games share one repository
and its releases.

The release is the newest of the repository's GitHub releases (its origin's): drafts left
out, pre-releases in, the highest version tag (v1.0.0-alpha.1 < v1.0.0-alpha.2 < v1.0.0-beta
< v1.0.0 < v1.0.1). Git tags that are not releases do not count. "Installed" is the commit
the installed timeslip.exe was built from (its build id), not the checkout's. A checkout
already past the release stays where it is: nothing ever moves back.

The update's "== " lines are the phases the launcher shows; the other lines are its detail.
Everything also goes to <install>\update.log.

For testing: TIMESLIP_UPDATE_RELEASES=<file> reads that JSON instead of GitHub's releases
list, and TIMESLIP_UPDATE_INSTALLED=<commit> stands for the installed build.
#>
param(
    [Parameter(Mandatory)][string]$Dest,
    [ValidateSet("ts2", "fp")][string]$Title = "ts2",
    [switch]$Check,
    [string]$Game = "",
    [switch]$NoShortcuts
)
# Continue, not Stop: Windows PowerShell turns a native program's every stderr line (git's
# progress) into an error, and Stop would end the script on the first. Failures are thrown.
$ErrorActionPreference = "Continue"
$repo = Split-Path $PSScriptRoot -Parent
$log = Join-Path $Dest "update.log"

function Say([string]$line) {
    [Console]::Out.WriteLine($line)
    [Console]::Out.Flush()
    if (-not $Check) { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }
}

function Invoke-RepoGit { & git.exe -C $repo @args 2>$null }

# A version tag as semver orders them; $null when the tag is not one.
function Parse-Version([string]$tag) {
    if ($tag -notmatch '^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$') { return $null }
    $pre = if ($Matches[4]) { $Matches[4].Split('.') } else { @() }
    return [pscustomobject]@{ Nums = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]); Pre = $pre }
}

function Compare-Version($a, $b) {
    for ($i = 0; $i -lt 3; $i++) { if ($a.Nums[$i] -ne $b.Nums[$i]) { return [Math]::Sign($a.Nums[$i] - $b.Nums[$i]) } }
    if (-not $a.Pre.Count -and -not $b.Pre.Count) { return 0 }
    if (-not $a.Pre.Count) { return 1 }                  # a release is above its pre-releases
    if (-not $b.Pre.Count) { return -1 }
    for ($i = 0; $i -lt [Math]::Min($a.Pre.Count, $b.Pre.Count); $i++) {
        $x = $a.Pre[$i]; $y = $b.Pre[$i]
        $xn = $x -match '^\d+$'; $yn = $y -match '^\d+$'
        if ($xn -and $yn) { if ([long]$x -ne [long]$y) { return [Math]::Sign([long]$x - [long]$y) } }
        elseif ($xn) { return -1 }                       # numbers sort below words
        elseif ($yn) { return 1 }
        elseif ($x -ne $y) { if ([string]::CompareOrdinal($x, $y) -lt 0) { return -1 } else { return 1 } }
    }
    return [Math]::Sign($a.Pre.Count - $b.Pre.Count)
}

# The newest release: its tag, or $null when there is none.
function Newest-Release {
    $json = $null
    if ($env:TIMESLIP_UPDATE_RELEASES) {
        $json = Get-Content -Raw -LiteralPath $env:TIMESLIP_UPDATE_RELEASES -ErrorAction Stop | ConvertFrom-Json
    } else {
        $url = Invoke-RepoGit remote get-url origin
        if ($url -notmatch 'github\.com[:/]+([^/]+)/([^/]+?)(\.git)?/?$') { throw "origin is not on GitHub ($url)" }
        $api = "https://api.github.com/repos/$($Matches[1])/$($Matches[2])/releases?per_page=30"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $json = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "timeslip-updater"; "Accept" = "application/vnd.github+json" } -TimeoutSec 30 -ErrorAction Stop
    }
    $best = $null; $bestV = $null
    foreach ($r in @($json)) {
        if ($r.draft) { continue }
        $v = Parse-Version $r.tag_name
        if (-not $v) { continue }
        if (-not $bestV -or (Compare-Version $v $bestV) -gt 0) { $best = $r.tag_name; $bestV = $v }
    }
    return $best
}

# The commit a release tag names, fetched so it can be compared.
function Release-Commit([string]$tag) {
    if (-not $env:TIMESLIP_UPDATE_RELEASES) {           # a test's tags are the checkout's own
        & git -C $repo fetch -q origin "+refs/tags/${tag}:refs/tags/${tag}" 2>$null
        if ($LASTEXITCODE) { throw "could not fetch $tag from origin" }
    }
    $c = Invoke-RepoGit rev-parse "refs/tags/$tag^{commit}"
    if (-not $c) { throw "$tag names no commit" }
    return $c.Trim()
}

# The commit the installed game was built from: its build id, "ts2 <commit> xbr <commit>"
# (Future Perfect's, "fp ts2 <commit> xbr <commit> USA", has the same in it).
function Installed-Commit {
    if ($env:TIMESLIP_UPDATE_INSTALLED) { $short = $env:TIMESLIP_UPDATE_INSTALLED }
    else {
        $exe = Join-Path $Dest $(if ($Title -eq "fp") { "timeslip_fp.exe" } else { "timeslip.exe" })
        if (-not (Test-Path $exe)) { return $null }
        $m = Select-String -LiteralPath $exe -Pattern 'ts2 ([0-9a-f]{12}) xbr [0-9a-f]{12}' -List
        if (-not $m) { return $null }
        $short = $m.Matches[0].Groups[1].Value
    }
    $c = Invoke-RepoGit rev-parse --verify --quiet "$short^{commit}"
    if ($c) { return $c.Trim() } else { return $null }
}

function Is-Ancestor([string]$a, [string]$b) {
    & git -C $repo merge-base --is-ancestor $a $b 2>$null
    return $LASTEXITCODE -eq 0
}

if ($Check) {
    try {
        $tag = Newest-Release
        if (-not $tag) { Say "none"; exit 0 }
        $rel = Release-Commit $tag
        $have = Installed-Commit
        if ($have -and ($have -eq $rel -or (Is-Ancestor $rel $have))) { Say "current $tag $rel" }
        else { Say "available $tag $rel" }
        exit 0
    } catch {
        Say ("error " + ($_.Exception.Message -replace '\s+', ' '))
        exit 0
    }
}

# ---- the update
try {
    Set-Content -LiteralPath $log -Value "Timeslip update, $(Get-Date -Format s)" -Encoding UTF8
    Say "== Asking GitHub for the newest release"
    $tag = Newest-Release
    if (-not $tag) { throw "no release has been published yet" }
    $rel = Release-Commit $tag
    Say "  $tag is $($rel.Substring(0, 12))"

    # Local changes are left alone: an update never builds over them. A submodule's own
    # untracked or changed files (recompose's xemu) are not changes to this checkout.
    $dirty = Invoke-RepoGit status --porcelain --untracked-files=no --ignore-submodules=dirty
    $dirtyR = & git -C (Join-Path $repo "recompose") status --porcelain --untracked-files=no --ignore-submodules=dirty 2>$null
    if ($dirty -or $dirtyR) { throw "the checkout at $repo has local changes; not updating over them" }

    Say "== Downloading $tag"
    & git -C $repo fetch -q origin 2>&1 | ForEach-Object { Say "  $_" }
    $head = (Invoke-RepoGit rev-parse HEAD).Trim()
    if ($head -eq $rel -or (Is-Ancestor $rel $head)) {
        Say "  the checkout already has $tag"
    } elseif (Is-Ancestor $head $rel) {
        $branch = (Invoke-RepoGit symbolic-ref --quiet --short HEAD)
        if (-not $branch) { throw "the checkout is not on a branch; not moving it" }
        & git -C $repo merge -q --ff-only $rel 2>&1 | ForEach-Object { Say "  $_" }
        if ($LASTEXITCODE) { throw "could not move $branch to $tag" }
        Say "  $branch moved to $tag"
    } else {
        throw "the checkout's history has gone another way from $tag; not moving it"
    }
    & git -C $repo submodule update --init recompose 2>&1 | ForEach-Object { Say "  $_" }
    if ($LASTEXITCODE) { throw "could not update the recompose submodule" }

    Say "== Recompiling the game from your disc"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_windows.ps1") -Title $Title -RelifFrom lift 2>&1 |
        ForEach-Object { Say "  $_" }
    if ($LASTEXITCODE) { throw "the build stopped (exit $LASTEXITCODE); see $log" }

    Say "== Installing"
    if (-not $Game) {
        $j = Join-Path $Dest "game"
        if (Test-Path $j) { $Game = (Get-Item $j).Target | Select-Object -First 1 }
    }
    $inst = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "install_windows.ps1"),
              "-Title", $Title, "-Dest", $Dest, "-KeepLauncher", "-NoArt")
    if ($Game) { $inst += @("-Game", $Game) }
    if ($NoShortcuts) { $inst += "-NoShortcuts" }
    & powershell.exe @inst 2>&1 | ForEach-Object { Say "  $_" }
    if ($LASTEXITCODE) { throw "the install stopped (exit $LASTEXITCODE)" }

    Say "== Updated to $tag"
    exit 0
} catch {
    Say ("== The update stopped: " + ($_.Exception.Message -replace '\s+', ' '))
    exit 1
}
