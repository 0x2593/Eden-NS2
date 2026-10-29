# Captures one window (by process id) to tools\out\screenshots\<timestamp>-<name>.png, even when it is behind other windows.
param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$Name)
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Win32 -Name Cap -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
'@
[void][Win32.Cap]::SetProcessDPIAware()
$hwnd = (Get-Process -Id $ProcessId).MainWindowHandle
if ($hwnd -eq 0) { return }
$r = New-Object Win32.Cap+RECT
[void][Win32.Cap]::GetWindowRect($hwnd, [ref]$r)
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
if ($w -le 0 -or $h -le 0) { return }
$bitmap = New-Object System.Drawing.Bitmap $w, $h
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$hdc = $graphics.GetHdc()
[void][Win32.Cap]::PrintWindow($hwnd, $hdc, 2)
$graphics.ReleaseHdc($hdc)
$dir = Join-Path $PSScriptRoot 'out\screenshots'
$path = Join-Path $dir ("{0}-{1}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Name)
$bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose()
$path
