using System.Diagnostics;
using System.Text;
using LumiKeyMapper.Core;

namespace LumiKeyMapper.Services;

public sealed record WindowEntry(string ProcessName, string Title, long Handle)
{
    public string Display => $"{ProcessName}  —  {Title}";
}

public sealed class WindowCatalog
{
    private nint lastWindow;
    private uint lastPid;
    private string lastProcess = "";
    public WindowContext Foreground()
    {
        var handle = Native.GetForegroundWindow();
        Native.GetWindowThreadProcessId(handle, out var pid);
        if (handle != lastWindow || pid != lastPid)
        {
            lastWindow = handle;
            lastPid = pid;
            lastProcess = ProcessName(pid);
        }
        return new(lastProcess, Title(handle), handle.ToInt64(), pid == Environment.ProcessId);
    }
    public static IReadOnlyList<WindowEntry> List()
    {
        var result = new List<WindowEntry>();
        Native.EnumWindows((window, _) =>
        {
            if (!Native.IsWindowVisible(window) || Native.GetWindow(window, 4) != 0) return true;
            Native.GetWindowThreadProcessId(window, out var pid);
            if (pid == Environment.ProcessId) return true;
            var title = Title(window);
            var name = ProcessName(pid);
            if (title.Length > 0 && name.Length > 0) result.Add(new(name, title, window.ToInt64()));
            return true;
        }, 0);
        return result.OrderBy(x=>x.ProcessName).ThenBy(x=>x.Title).ToArray();
    }
    private static string ProcessName(uint id)
    {
        try { using var process = Process.GetProcessById((int)id); return process.ProcessName; }
        catch { return ""; }
    }
    private static string Title(nint handle)
    {
        var text = new StringBuilder(1024);
        Native.GetWindowText(handle, text, text.Capacity);
        return text.ToString();
    }
}
