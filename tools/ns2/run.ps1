# One verify cycle: optional build -> launch a game -> periodic window captures -> log summary.
# Only the Eden process it starts is stopped. Output goes to tools\out\.
#   .\run.ps1 -Game 'D:\Games\Title\updates\<version>\exefs\main' [-Build] [-Tag name] [-RunSeconds 90]
#             [-EnvVars 'EDEN_NATIVE_FRAME_STATS=1;EDEN_NATIVE_TIC_TRACE=1']
param([Parameter(Mandatory)][string]$Game, [string]$Root = (Join-Path $PSScriptRoot '..\..'),
      [string]$Tag = 'run', [int]$RunSeconds = 90, [switch]$Build, [string]$EnvVars = '')
$ErrorActionPreference = 'Continue'
$root = (Resolve-Path $Root).Path
$out = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Force (Join-Path $out 'screenshots'), (Join-Path $out 'dumps') | Out-Null
$buildLog = Join-Path $out 'build-last.log'
$edenLog = "$env:APPDATA\eden\log\eden_log.txt"

if ($Build) {
    # MSYS2 MINGW64 build of an already-configured build\ directory.
    $toUnix = { param($path) '/' + (($path -replace ':', '') -replace '\\', '/') }
    $buildDir = & $toUnix (Join-Path $root 'build')
    $logUnix = & $toUnix $buildLog
    & 'C:\msys64\usr\bin\bash.exe' -lc "export MSYSTEM=MINGW64; source /etc/profile; cd $buildDir && ninja yuzu > $logUnix 2>&1; echo BUILD_EXIT=`$? >> $logUnix"
    $buildExit = (Select-String -Path $buildLog -Pattern 'BUILD_EXIT=(\d+)').Matches[0].Groups[1].Value
    "build exit: $buildExit"
    if ($buildExit -ne '0') { Get-Content $buildLog | Select-String ' error|FAILED' | Select-Object -First 15; return }
}

foreach ($kv in ($EnvVars -split ';' | Where-Object { $_ })) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v }
$work = Join-Path $out "dumps\frames-$Tag"
New-Item -ItemType Directory -Force $work | Out-Null
$start = Get-Date
$eden = Start-Process (Join-Path $root 'build\bin\eden.exe') -PassThru -WorkingDirectory $work -ArgumentList '-g', "`"$Game`""
$checkpoints = @(30, 60, $RunSeconds) | Where-Object { $_ -le $RunSeconds } | Sort-Object -Unique
foreach ($t in $checkpoints) {
    while (((Get-Date) - $start).TotalSeconds -lt $t) {
        if ($eden.HasExited) { break }
        Start-Sleep -Seconds 2
    }
    if ($eden.HasExited) { "eden exited early with code $($eden.ExitCode) at $([int]((Get-Date) - $start).TotalSeconds)s"; break }
    & (Join-Path $PSScriptRoot 'wincap.ps1') -ProcessId $eden.Id -Name "$Tag-game-${t}s" | Out-Null
}
$running = -not $eden.HasExited
if ($running) { $eden.Kill() }
Start-Sleep -Seconds 2
Copy-Item $edenLog (Join-Path $out "dumps\log-$Tag.txt") -Force
"running at end: $running"
"presents: $((Select-String -Path $edenLog -Pattern 'Native image queued').Count)"
"skipped-draw groups: $((Select-String -Path $edenLog -Pattern 'Native graphics draw skipped').Count)"
"shader lowering failures: $((Select-String -Path $edenLog -Pattern 'lowering failed at').Count)"
"crash/panic: $((Select-String -Path $edenLog -Pattern 'LogBacktrace|PANIC').Count)"
Get-ChildItem (Join-Path $out 'screenshots') -Filter "*$Tag*" | Select-Object -ExpandProperty Name
