# Boots a game, presses A (keyboard C) through the mode-select menu, then captures the load.
# Only the Eden process it starts is stopped. Output goes to tools\ns2\out\.
#   .\load.ps1 -Game 'D:\Games\Title\updates\<version>\exefs\main' [-Root <eden checkout>] [-Tag name]
param([Parameter(Mandatory)][string]$Game, [string]$Root = (Join-Path $PSScriptRoot '..\..'),
      [string]$Tag = 'load', [int[]]$PressAt = @(75, 80), [int[]]$Shots = @(70, 100, 140, 180, 240))
$out = Join-Path $PSScriptRoot 'out'
$work = Join-Path $out "dumps\frames-$Tag"
New-Item -ItemType Directory -Force $work, (Join-Path $out 'screenshots') | Out-Null
$eden = Start-Process (Join-Path (Resolve-Path $Root).Path 'build\bin\eden.exe') -PassThru -WorkingDirectory $work -ArgumentList '-g', "`"$Game`""
$start = Get-Date
$steps = @($Shots | ForEach-Object { @{ t = $_; key = $null } }) + @($PressAt | ForEach-Object { @{ t = $_; key = 'C' } }) | Sort-Object { $_.t }
foreach ($step in $steps) {
    while (((Get-Date) - $start).TotalSeconds -lt $step.t -and -not $eden.HasExited) { Start-Sleep 2 }
    if ($eden.HasExited) { "eden exited early with code $($eden.ExitCode) at $([int]((Get-Date) - $start).TotalSeconds)s"; break }
    if ($step.key) { & (Join-Path $PSScriptRoot 'keys.ps1') -ProcessId $eden.Id -Keys $step.key | Out-Null }
    else { & (Join-Path $PSScriptRoot 'wincap.ps1') -ProcessId $eden.Id -Name "$Tag-$($step.t)s" | Out-Null }
}
$running = -not $eden.HasExited
if ($running) { $eden.Kill() }
Start-Sleep -Seconds 2
$log = Join-Path $out "dumps\log-$Tag.txt"
Copy-Item "$env:APPDATA\eden\log\eden_log.txt" $log -Force
"running at end: $running"
"crash/panic: $((Select-String -Path $log -Pattern 'LogBacktrace|PANIC').Count)"
"rejected GPU requests: $((Select-String -Path $log -Pattern 'rejected:').Count)"
"shader lowering failures: $((Select-String -Path $log -Pattern 'lowering failed at').Count)"
"semaphore suspends: $((Select-String -Path $log -Pattern 'suspended for semaphore').Count)"
Get-ChildItem (Join-Path $out 'screenshots') -Filter "*$Tag*" | Select-Object -ExpandProperty Name
