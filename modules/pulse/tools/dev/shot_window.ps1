param([string]$out, [string]$cls = "FLUTTER_RUNNER_WIN32_WINDOW", [string]$title = $null, [int]$pad = 30)
# Screenshots a window (by class / title) including whatever is around it (screen copy, so
# layered/transparent windows like the speaker overlay are captured correctly).
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
public struct RECT { public int L, T, R, B; } }
"@
[W]::SetProcessDPIAware() | Out-Null
$h = if ($title) { [W]::FindWindow($cls, $title) } else { [W]::FindWindow($cls, [NullString]::Value) }
if ($h -eq [IntPtr]::Zero) { Write-Output "no window"; exit 1 }
$r = New-Object W+RECT; [W]::GetWindowRect($h, [ref]$r) | Out-Null
$x = $r.L - $pad; $y = $r.T - $pad; $w = $r.R - $r.L + 2 * $pad; $hh = $r.B - $r.T + 2 * $pad
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $hh))
$bmp.Save($out); Write-Output "saved $w x $hh"
