# Focuses a process's main window and taps keys (virtual-key letters/digits), e.g. -Keys C,C,M
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string[]]$Keys, [int]$HoldMs = 120, [int]$GapMs = 700)
Add-Type -Namespace Win32 -Name Keys -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
'@
$hwnd = (Get-Process -Id $ProcessId).MainWindowHandle
if ($hwnd -eq 0) { "no window"; return }
$foreground = [Win32.Keys]::GetForegroundWindow()
$fgThread = [Win32.Keys]::GetWindowThreadProcessId($foreground, [IntPtr]::Zero)
$me = [Win32.Keys]::GetCurrentThreadId()
[void][Win32.Keys]::AttachThreadInput($me, $fgThread, $true)
[void][Win32.Keys]::ShowWindow($hwnd, 9)
[void][Win32.Keys]::SetForegroundWindow($hwnd)
[void][Win32.Keys]::AttachThreadInput($me, $fgThread, $false)
Start-Sleep -Milliseconds 500
"foreground ok: $([Win32.Keys]::GetForegroundWindow() -eq $hwnd)"
foreach ($key in $Keys) {
    $vk = [byte][char]$key.ToUpper()
    $scan = [byte][Win32.Keys]::MapVirtualKey($vk, 0)
    [Win32.Keys]::keybd_event($vk, $scan, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $HoldMs
    [Win32.Keys]::keybd_event($vk, $scan, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $GapMs
}
