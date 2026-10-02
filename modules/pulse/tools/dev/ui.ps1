param([string]$action, [int]$x = 0, [int]$y = 0, [string]$text = "", [string]$title = "Pulse")
# Minimal UI driver for manual end-to-end checks: focus the Pulse window, click / type.
Add-Type @"
using System; using System.Runtime.InteropServices;
public class U { [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
[DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, int f, int e);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr p);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
public struct RECT { public int L, T, R, B; } }
"@
[U]::SetProcessDPIAware() | Out-Null
$h = [U]::FindWindow("FLUTTER_RUNNER_WIN32_WINDOW", $title)
if ($action -eq "place") { [U]::ShowWindow($h, 9) | Out-Null; [U]::MoveWindow($h, 20, 20, 2040, 1230, $true) | Out-Null; exit 0 }
for ($i = 0; $i -lt 5 -and [U]::GetForegroundWindow() -ne $h; $i++) {
  $fg = [U]::GetForegroundWindow(); $t1 = [U]::GetWindowThreadProcessId($fg, [IntPtr]::Zero); $t2 = [U]::GetCurrentThreadId()
  [U]::AttachThreadInput($t2, $t1, $true) | Out-Null; [U]::keybd_event(0x12,0,0,0); [U]::BringWindowToTop($h) | Out-Null
  [U]::SetForegroundWindow($h) | Out-Null; [U]::keybd_event(0x12,0,2,0); [U]::AttachThreadInput($t2, $t1, $false) | Out-Null
  Start-Sleep -Milliseconds 150 }
Start-Sleep -Milliseconds 100
$r = New-Object U+RECT; [U]::GetWindowRect($h, [ref]$r) | Out-Null
switch ($action) {
  "click" { [U]::SetCursorPos($r.L + $x, $r.T + $y) | Out-Null; Start-Sleep -Milliseconds 80; [U]::mouse_event(2,0,0,0,0); [U]::mouse_event(4,0,0,0,0) }
  "type" { Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait($text) }
}
