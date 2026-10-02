using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using LumiKeyMapper.Core;

namespace LumiKeyMapper.Services;

public sealed class InputService : IDisposable
{
    private readonly Thread thread;
    private readonly ManualResetEventSlim ready = new();
    private readonly WindowCatalog windows = new();
    private readonly HashSet<InputKey> capturedDown = [];
    private readonly Native.HookProc keyboardProc;
    private readonly Native.HookProc mouseProc;
    private Dispatcher dispatcher = null!;
    private MappingEngine engine = null!;
    private nint keyboardHook, mouseHook;
    private Exception? startupError;
    private Action<InputKey?>? captureCallback;
    private InputKey? candidate;
    private DateTime captureDeadline;
    private bool editing, faulted, disposed;
    public event Action<bool>? PauseChanged;
    public event Action<string>? Error;
    public InputService()
    {
        keyboardProc = KeyboardCallback;
        mouseProc = MouseCallback;
        thread = new Thread(Run) { IsBackground = true, Name = "Lumi input" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException("输入服务启动超时。");
        if (startupError != null) throw new InvalidOperationException("无法启用键鼠监听。", startupError);
    }
    private void Run()
    {
        try
        {
            dispatcher = Dispatcher.CurrentDispatcher;
            engine = new(Send);
            engine.StateChanged += () => PauseChanged?.Invoke(engine.IsPaused);
            keyboardHook = Native.SetWindowsHookEx(13, keyboardProc, Native.GetModuleHandle(null), 0);
            mouseHook = Native.SetWindowsHookEx(14, mouseProc, Native.GetModuleHandle(null), 0);
            if (keyboardHook == 0 || mouseHook == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            var timer = new DispatcherTimer(TimeSpan.FromMilliseconds(75), DispatcherPriority.Background, (_,_)=>
            {
                engine.SetContext(windows.Foreground());
                if (captureCallback != null && DateTime.UtcNow > captureDeadline) EndCapture(null);
            }, dispatcher);
            timer.Start();
            ready.Set();
            Dispatcher.Run();
            timer.Stop();
        }
        catch (Exception ex) { startupError = ex; ready.Set(); Error?.Invoke(ex.Message); }
        finally
        {
            engine?.ReleaseAll();
            if (keyboardHook != 0) Native.UnhookWindowsHookEx(keyboardHook);
            if (mouseHook != 0) Native.UnhookWindowsHookEx(mouseHook);
        }
    }
    public void Configure(AppSettings settings)
    {
        var rules = settings.Rules.ToArray();
        var pause = settings.PauseKey;
        var enabled = settings.Enabled;
        dispatcher.Invoke(()=>
        {
            faulted = false;
            engine.Configure(rules, pause, enabled);
            engine.Suspend(editing || captureCallback != null);
        });
    }
    public void SetEditing(bool value) => dispatcher.Invoke(()=> { editing = value; engine.Suspend(value || captureCallback != null || faulted); });
    public void Capture(Action<InputKey?> callback) => dispatcher.Invoke(()=>
    {
        EndCapture(null);
        candidate = null;
        captureCallback = callback;
        captureDeadline = DateTime.UtcNow.AddSeconds(10);
        engine.Suspend(true);
    });
    public void CancelCapture() => dispatcher.Invoke(()=>EndCapture(null));
    private void EndCapture(InputKey? key)
    {
        var callback = captureCallback;
        captureCallback = null;
        candidate = null;
        engine.Suspend(editing || faulted);
        callback?.Invoke(key);
    }
    private bool Handle(InputSignal signal)
    {
        try
        {
            if (!signal.IsDown && capturedDown.Remove(signal.Key))
            {
                // A key may already have been held when recording began. Clear its
                // old engine state even though the recorded release is swallowed.
                engine.Process(signal, windows.Foreground());
                if (candidate == signal.Key) EndCapture(signal.Key);
                return true;
            }
            if (captureCallback != null)
            {
                if (signal.IsDown)
                {
                    // Do not record auto-repeat from keys held before recording began;
                    // their matching release must still reach the normal input path.
                    if (!signal.Key.IsPulse && engine.IsPhysicallyDown(signal.Key))
                        return engine.Process(signal, windows.Foreground());
                    if (signal.Key.IsPulse) EndCapture(signal.Key);
                    else { capturedDown.Add(signal.Key); candidate ??= signal.Key; }
                    return true;
                }
                // Pre-existing physical holds still need their normal release.
                return engine.Process(signal, windows.Foreground());
            }
            if (capturedDown.Contains(signal.Key)) return true;
            var result = engine.Process(signal, windows.Foreground());
            if (faulted) { engine.Suspend(true); return false; }
            return result;
        }
        catch (Exception ex)
        {
            faulted = true;
            engine.Suspend(true);
            Error?.Invoke($"映射已暂停：{ex.Message}");
            return false;
        }
    }
    private nint KeyboardCallback(int code, nuint message, nint data)
    {
        if (code >= 0)
        {
            var key = Marshal.PtrToStructure<Native.KeyboardHook>(data);
            if (key.Extra != Native.Marker && message is 0x100 or 0x101 or 0x104 or 0x105)
            {
                var vk = (int)key.Vk;
                if (vk == 0x10) vk = key.Scan == 0x36 ? 0xA1 : 0xA0;
                if (vk == 0x11) vk = (key.Flags & 1) != 0 ? 0xA3 : 0xA2;
                if (vk == 0x12) vk = (key.Flags & 1) != 0 ? 0xA5 : 0xA4;
                if (Handle(new(new(InputKind.Keyboard, vk), message is 0x100 or 0x104))) return 1;
            }
        }
        return Native.CallNextHookEx(0, code, message, data);
    }
    private nint MouseCallback(int code, nuint message, nint data)
    {
        if (code >= 0 && message != 0x200)
        {
            var mouse = Marshal.PtrToStructure<Native.MouseHook>(data);
            if (mouse.Extra != Native.Marker)
            {
                InputSignal? signal = message switch
                {
                    0x201 => new(new(InputKind.Mouse,1),true), 0x202 => new(new(InputKind.Mouse,1),false),
                    0x204 => new(new(InputKind.Mouse,2),true), 0x205 => new(new(InputKind.Mouse,2),false),
                    0x207 => new(new(InputKind.Mouse,3),true), 0x208 => new(new(InputKind.Mouse,3),false),
                    0x20B => new(new(InputKind.Mouse,(mouse.Data >> 16) == 1 ? 4 : 5),true),
                    0x20C => new(new(InputKind.Mouse,(mouse.Data >> 16) == 1 ? 4 : 5),false),
                    0x20A => new(new(InputKind.Wheel,(short)(mouse.Data >> 16) > 0 ? 1 : 2),true, Math.Abs((int)(short)(mouse.Data >> 16))),
                    0x20E => new(new(InputKind.Wheel,(short)(mouse.Data >> 16) > 0 ? 4 : 3),true, Math.Abs((int)(short)(mouse.Data >> 16))),
                    _ => null
                };
                if (signal.HasValue && Handle(signal.Value)) return 1;
            }
        }
        return Native.CallNextHookEx(0, code, message, data);
    }
    private void Send(OutputSignal signal)
    {
        var key = signal.Key;
        Native.Input input;
        if (key.Kind == InputKind.Keyboard)
        {
            var extended = key.Code is 0xA3 or 0xA5 or 0x21 or 0x22 or 0x23 or 0x24 or 0x25 or 0x26 or 0x27 or 0x28 or 0x2D or 0x2E or 0x5B or 0x5C or 0x5D or 0x6F or 0x90 or 0x2C;
            input = new() { Type=1, Value = new() { Keyboard = new() { Vk=(ushort)key.Code, Scan=(ushort)Native.MapVirtualKey((uint)key.Code,0), Flags=(signal.IsDown ? 0u : 2u) | (extended ? 1u : 0u), Extra=Native.Marker } } };
        }
        else
        {
            uint flags = key.Kind == InputKind.Wheel ? (key.Code <= 2 ? 0x800u : 0x1000u) : key.Code switch
            {
                1 => signal.IsDown ? 2u : 4u, 2 => signal.IsDown ? 8u : 16u, 3 => signal.IsDown ? 32u : 64u, _ => signal.IsDown ? 128u : 256u
            };
            uint data = key.Kind == InputKind.Wheel ? unchecked((uint)((key.Code is 2 or 3 ? -1 : 1) * signal.Delta)) : key.Code switch { 4=>1u,5=>2u,_=>0u };
            input = new() { Type=0, Value=new() { Mouse=new() { Flags=flags, Data=data, Extra=Native.Marker } } };
        }
        if (Native.SendInput(1,[input],Marshal.SizeOf<Native.Input>()) == 0 && !faulted)
        {
            faulted = true;
            Error?.Invoke("Windows 阻止了按键发送，映射已暂停。若目标应用以管理员身份运行，请以管理员身份重新启动 LumiKeyMapper，再开启映射。");
        }
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (dispatcher is not null && !dispatcher.HasShutdownStarted)
            dispatcher.Invoke(()=> { EndCapture(null); engine.ReleaseAll(); dispatcher.BeginInvokeShutdown(DispatcherPriority.Send); });
        thread.Join(TimeSpan.FromSeconds(3));
        ready.Dispose();
    }
}
