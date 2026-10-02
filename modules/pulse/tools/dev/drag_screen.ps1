param([int]$x1, [int]$y1, [int]$x2, [int]$y2)
Add-Type @"
using System; using System.Runtime.InteropServices;
public class M { [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[M]::SetProcessDPIAware() | Out-Null
[M]::SetCursorPos($x1, $y1) | Out-Null; Start-Sleep -Milliseconds 200
[M]::mouse_event(2,0,0,0,0)
for ($i = 1; $i -le 20; $i++) { [M]::SetCursorPos($x1 + ($x2-$x1)*$i/20, $y1 + ($y2-$y1)*$i/20) | Out-Null; Start-Sleep -Milliseconds 15 }
[M]::mouse_event(4,0,0,0,0)
