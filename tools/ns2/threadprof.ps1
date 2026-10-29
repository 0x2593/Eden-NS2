# Samples per-thread CPU time of a process over an interval and prints the busiest threads by name.
param([Parameter(Mandatory)][int]$ProcessId, [int]$Seconds = 10)
Add-Type -Namespace Win32 -Name Thr -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr OpenThread(uint access, bool inherit, uint id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern int GetThreadDescription(IntPtr h, out IntPtr desc);
[DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
'@
function Get-Name([int]$id) {
    $h = [Win32.Thr]::OpenThread(0x1000, $false, $id)
    if ($h -eq [IntPtr]::Zero) { return '' }
    $p = [IntPtr]::Zero
    $name = ''
    if ([Win32.Thr]::GetThreadDescription($h, [ref]$p) -ge 0 -and $p -ne [IntPtr]::Zero) {
        $name = [Runtime.InteropServices.Marshal]::PtrToStringUni($p)
        [void][Win32.Thr]::LocalFree($p)
    }
    [void][Win32.Thr]::CloseHandle($h)
    $name
}
$before = @{}
(Get-Process -Id $ProcessId).Threads | ForEach-Object { $before[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
Start-Sleep -Seconds $Seconds
(Get-Process -Id $ProcessId).Threads | ForEach-Object {
    $prev = if ($before.ContainsKey($_.Id)) { $before[$_.Id] } else { 0 }
    [pscustomobject]@{ Id = $_.Id; Name = (Get-Name $_.Id); Percent = [math]::Round(($_.TotalProcessorTime.TotalMilliseconds - $prev) / ($Seconds * 10), 1) }
} | Sort-Object Percent -Descending | Select-Object -First 10 | Format-Table -AutoSize
