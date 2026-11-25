<#
Builds Timeslip on Windows the way Linux builds it: zig (clang) + Ninja, one configuration
in build\<Config>, with the toolchain Recompose's release pins (recompose
tools\release\fetch_toolchain.py).

    tools\build_windows.ps1 [-Config Release] [-Toolchain <dir>] [-RelifFrom <stage>] [-Vulkan] [-Reconfigure]

-Toolchain is the fetched toolchain's folder (the one with bin\, cmake\ and ninja\ in it).
Once build\<Config> is configured it is read from there, so a rebuild needs no arguments.
Its Python (the toolchain's, beside it, with capstone) lifts the game when that is needed.
-RelifFrom lift lifts the game again from that stage (after the overrides, recomp_manual.c
or the toolkit's lifter change; the updater always does).
-Vulkan configures the Vulkan renderer in (Timeslip's default; needs recompose\third_party\dxc).
#>
param(
    [string]$Config = "Release",
    [string]$Toolchain = "",
    [string]$RelifFrom = "",
    [switch]$Vulkan,
    [switch]$Reconfigure
)
$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent
$build = Join-Path $repo "build\$Config"
$cache = Join-Path $build "CMakeCache.txt"
$fwd = { param($p) $p -replace '\\', '/' }

# The toolchain: as given, else where the configured build's Ninja is.
if (-not $Toolchain -and (Test-Path $cache)) {
    $make = (Select-String -Path $cache -Pattern '^CMAKE_MAKE_PROGRAM:\w+=(.+)$' | Select-Object -First 1)
    if ($make) {
        $ninja = $make.Matches[0].Groups[1].Value -replace '/', '\'
        $Toolchain = Split-Path (Split-Path (Split-Path $ninja -Parent) -Parent) -Parent   # ...\ninja\bin\ninja.exe
    }
}
if (-not $Toolchain -or -not (Test-Path (Join-Path $Toolchain "bin\zcc.exe"))) {
    throw "no toolchain: pass -Toolchain <dir> (recompose tools\release\fetch_toolchain.py fetches one)"
}
$py = Join-Path (Split-Path $Toolchain -Parent) "python\python.exe"
if (-not (Test-Path $py)) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $py) { throw "no Python: the toolchain's (python\ beside it) or py" }

$env:ZIG_GLOBAL_CACHE_DIR = Join-Path (Split-Path $Toolchain -Parent) "zig-cache"
$env:ZIG_LOCAL_CACHE_DIR = $env:ZIG_GLOBAL_CACHE_DIR
$env:CMAKE_GENERATOR = "Ninja"
$env:PATH = "$Toolchain\cmake\bin;$Toolchain\ninja\bin;$Toolchain\bin;$env:PATH"

if ($Reconfigure -and (Test-Path $cache)) { Remove-Item $cache }
if (-not (Test-Path $cache)) {
    $cfg = @(
        "-S", $repo, "-B", $build, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=$Config",
        "-DCMAKE_MAKE_PROGRAM=$(& $fwd "$Toolchain\ninja\bin\ninja.exe")",
        "-DCMAKE_C_COMPILER=$(& $fwd "$Toolchain\bin\zcc.exe")",
        "-DCMAKE_CXX_COMPILER=$(& $fwd "$Toolchain\bin\zc++.exe")",
        "-DCMAKE_AR=$(& $fwd "$Toolchain\bin\zar.exe")",
        "-DCMAKE_RANLIB=$(& $fwd "$Toolchain\bin\zranlib.exe")",
        "-DCMAKE_RC_COMPILER=$(& $fwd "$Toolchain\bin\zrc.exe")"
    )
    # SDL's SIMD probes, answered as the release does (each costs ~2 min under zig on Windows).
    foreach ($f in "SSE3", "SSE4_1", "SSE4_2", "AVX", "AVX2", "AVX512F") { $cfg += "-DCOMPILER_SUPPORTS_$f=1" }
    $cfg += "-DXBOXRECOMP_VULKAN=$(if ($Vulkan) { 'ON' } else { 'OFF' })"
    & "$Toolchain\cmake\bin\cmake.exe" @cfg
    if ($LASTEXITCODE) { throw "configure failed" }
}
# build.py: lifts if needed (or again, -RelifFrom), then builds the configured folder.
$ErrorActionPreference = "Continue"   # build.py logs to stderr; PowerShell would stop on it
if ($RelifFrom) { & $py "$repo\scripts\build.py" --config $Config --relift --from $RelifFrom }
else { & $py "$repo\scripts\build.py" --config $Config }
exit $LASTEXITCODE
