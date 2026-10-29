# Captures the whole virtual desktop to tools\out\screenshots\<timestamp>-<name>.png
param([Parameter(Mandatory)][string]$Name)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Win32 -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][Win32.Dpi]::SetProcessDPIAware()
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
$dir = Join-Path $PSScriptRoot 'out\screenshots'
New-Item -ItemType Directory -Force $dir | Out-Null
$path = Join-Path $dir ("{0}-{1}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Name)
$bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $bitmap.Dispose()
$path
