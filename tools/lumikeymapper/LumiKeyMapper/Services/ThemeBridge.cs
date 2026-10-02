using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace LumiKeyMapper.Services;

/// <summary>Colour set shared with the CML launcher (theme.json).</summary>
public sealed record ThemePalette
{
    public bool Dark { get; init; }
    public Color Bg { get; init; }
    public Color Surface { get; init; }
    public Color Panel { get; init; }
    public Color Text { get; init; }
    public Color Muted { get; init; }
    public Color Line { get; init; }
    public Color Field { get; init; }
    public Color Accent { get; init; }
    public Color Accent2 { get; init; }
    public Color OnAccent { get; init; }
    public Color Paper { get; init; }
    public Color Ink { get; init; }
    public string Id { get; init; } = "default";
    public string Name { get; init; } = "默认";
    public string Version { get; init; } = "";

    public static ThemePalette Light { get; } = new()
    {
        Dark=false, Bg=Hex("#f4f7fa"), Surface=Hex("#ffffff"), Panel=Hex("#ffffff"), Text=Hex("#1d2233"), Muted=Hex("#6b7280"),
        Line=Hex("#e3e7ec"), Field=Hex("#f3f5f8"), Accent=Hex("#4fa3d9"), Accent2=Hex("#7fd3c8"), OnAccent=Hex("#ffffff"),
        Paper=Hex("#ffffff"), Ink=Hex("#1d2233")
    };
    public static ThemePalette DarkDefault { get; } = new()
    {
        Dark=true, Bg=Hex("#14171d"), Surface=Hex("#1b1f27"), Panel=Hex("#1f242d"), Text=Hex("#e7eaf0"), Muted=Hex("#98a1b0"),
        Line=Hex("#2c323d"), Field=Hex("#252a34"), Accent=Hex("#4fa3d9"), Accent2=Hex("#7fd3c8"), OnAccent=Hex("#ffffff"),
        Paper=Hex("#1f242d"), Ink=Hex("#e7eaf0"), Name="默认（深色）"
    };
    internal static Color Hex(string value) => TryHex(value, out var color) ? color : Colors.Magenta;
    internal static bool TryHex(string? value, out Color color)
    {
        color = default;
        if (string.IsNullOrWhiteSpace(value)) return false;
        var s = value.Trim().TrimStart('#');
        if (s.Length == 3) s = string.Concat(s.Select(c=>$"{c}{c}"));
        if (s.Length != 6 && s.Length != 8) return false;
        if (!uint.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out var n)) return false;
        color = s.Length == 6
            ? Color.FromRgb((byte)(n >> 16), (byte)(n >> 8), (byte)n)
            : Color.FromRgb((byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8)); // #rrggbbaa: alpha ignored
        return true;
    }
}

/// <summary>
/// Follows the CML launcher theme. Source: env CML_THEME_FILE, else %APPDATA%\CML\theme.json, else built-in defaults.
/// Colours are pushed into Application resources as brushes, so every DynamicResource reference updates live.
/// </summary>
public static class ThemeBridge
{
    public const string EnvironmentVariable = "CML_THEME_FILE";
    private static FileSystemWatcher? watcher;
    private static DispatcherTimer? debounce, directoryPoll;
    private static int retries;
    public static ThemePalette Current { get; private set; } = ThemePalette.Light;
    /// <summary>True when the current colours came from a theme file.</summary>
    public static bool FromFile { get; private set; }
    public static string FilePath { get; private set; } = DefaultPath();
    public static event Action? Changed;

    public static string DefaultPath()
    {
        var env = Environment.GetEnvironmentVariable(EnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(env)) return Path.GetFullPath(Environment.ExpandEnvironmentVariables(env.Trim().Trim('"')));
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CML", "theme.json");
    }

    /// <summary>Loads the theme file once (if present), applies it and starts watching for changes.</summary>
    public static void Start(string? path = null)
    {
        Stop();
        FilePath = path ?? DefaultPath();
        if (!TryLoadFile()) Apply(ThemePalette.Light, false);
        Watch();
    }

    public static void Stop()
    {
        watcher?.Dispose(); watcher = null;
        debounce?.Stop(); debounce = null;
        directoryPoll?.Stop(); directoryPoll = null;
    }

    /// <summary>Parses launcher theme JSON. Unknown fields are ignored; missing colours fall back to the built-in light / dark defaults. Returns null when the JSON is invalid.</summary>
    public static ThemePalette? Parse(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions { AllowTrailingCommas=true, CommentHandling=JsonCommentHandling.Skip });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var dark = root.TryGetProperty("dark", out var d) && d.ValueKind == JsonValueKind.True;
            var b = dark ? ThemePalette.DarkDefault : ThemePalette.Light;
            Color C(string key, Color fallback) =>
                root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String && ThemePalette.TryHex(v.GetString(), out var c) ? c : fallback;
            string S(string key, string fallback) =>
                root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? fallback : fallback;
            var surface = C("surface", b.Surface);
            var text = C("text", b.Text);
            return new ThemePalette
            {
                Dark=dark, Bg=C("bg", b.Bg), Surface=surface, Panel=C("panel", b.Panel), Text=text, Muted=C("muted", b.Muted),
                Line=C("line", b.Line), Field=C("field", b.Field), Accent=C("accent", b.Accent), Accent2=C("accent2", b.Accent2),
                OnAccent=C("onAccent", b.OnAccent), Paper=C("paper", surface), Ink=C("ink", text),
                Id=S("id", b.Id), Name=S("name", b.Name), Version=S("version", "")
            };
        }
        catch (JsonException) { return null; }
    }

    /// <summary>Applies JSON text; keeps the current colours and returns false on parse errors.</summary>
    public static bool ApplyJson(string json, bool fromFile = false)
    {
        var palette = Parse(json);
        if (palette == null) return false;
        Apply(palette, fromFile);
        return true;
    }

    public static void Apply(ThemePalette p, bool fromFile = false)
    {
        Current = p;
        FromFile = fromFile;
        var resources = Application.Current?.Resources;
        if (resources == null) return;
        void Set(string key, Color color) { var brush = new SolidColorBrush(color); brush.Freeze(); resources[key] = brush; resources[key + "Color"] = color; }
        Set("BgBrush", p.Bg);
        Set("SurfaceBrush", p.Surface);
        Set("PanelBrush", p.Panel);
        Set("TextBrush", p.Text);
        Set("MutedBrush", p.Muted);
        Set("LineBrush", p.Line);
        Set("FieldBrush", p.Field);
        Set("AccentBrush", p.Accent);
        Set("Accent2Brush", p.Accent2);
        Set("OnAccentBrush", p.OnAccent);
        Set("PaperBrush", p.Paper);
        Set("InkBrush", p.Ink);
        // Derived tones, computed from the launcher palette so they always match it.
        Set("AccentSoftBrush", Mix(p.Surface, p.Accent, p.Dark ? 0.22 : 0.13));
        Set("AccentHoverBrush", Mix(p.Accent, p.Dark ? Colors.White : Colors.Black, 0.10));
        Set("AccentPressedBrush", Mix(p.Accent, p.Dark ? Colors.White : Colors.Black, 0.20));
        Set("Accent2SoftBrush", Mix(p.Surface, p.Accent2, p.Dark ? 0.22 : 0.20));
        Set("HoverBrush", Mix(p.Surface, p.Text, p.Dark ? 0.08 : 0.05));
        Set("PressedBrush", Mix(p.Surface, p.Text, p.Dark ? 0.14 : 0.09));
        Set("KeyCapBrush", p.Dark ? Mix(p.Field, Colors.White, 0.04) : Mix(p.Field, Colors.White, 0.55));
        Set("KeyCapEdgeBrush", Mix(p.Line, p.Text, p.Dark ? 0.10 : 0.14));
        Set("RailBrush", Mix(p.Bg, p.Surface, 0.5));
        Set("SuccessBrush", Mix(p.Accent2, p.Dark ? Colors.White : Colors.Black, p.Dark ? 0.0 : 0.18));
        Set("WarningBrush", Color.FromRgb(0xE8, 0xA3, 0x3D));
        Set("WarningSoftBrush", Mix(p.Surface, Color.FromRgb(0xE8, 0xA3, 0x3D), p.Dark ? 0.20 : 0.15));
        Set("DangerBrush", p.Dark ? Color.FromRgb(0xFF, 0x6B, 0x6B) : Color.FromRgb(0xD9, 0x3F, 0x3F));
        Set("DangerSoftBrush", Mix(p.Surface, Color.FromRgb(0xE5, 0x48, 0x4D), p.Dark ? 0.22 : 0.12));
        Set("ToastBrush", p.Dark ? Mix(p.Panel, Colors.White, 0.08) : Mix(p.Text, Colors.Black, 0.05));
        Set("OnToastBrush", p.Dark ? p.Text : Colors.White);
        var scrim = new SolidColorBrush(Color.FromArgb((byte)(p.Dark ? 150 : 90), 8, 10, 16)); scrim.Freeze();
        resources["ScrimBrush"] = scrim;
        Changed?.Invoke();
    }

    public static Color Mix(Color a, Color b, double amount) => Color.FromRgb(
        (byte)Math.Round(a.R + (b.R - a.R) * amount), (byte)Math.Round(a.G + (b.G - a.G) * amount), (byte)Math.Round(a.B + (b.B - a.B) * amount));

    private static bool TryLoadFile()
    {
        if (!File.Exists(FilePath)) return false;
        string text;
        try
        {
            using var stream = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var reader = new StreamReader(stream);
            text = reader.ReadToEnd();
        }
        catch (UnauthorizedAccessException) { return false; }
        return ApplyJson(text, true);
    }

    private static void Watch()
    {
        var dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
        debounce = new DispatcherTimer(TimeSpan.FromMilliseconds(150), DispatcherPriority.Normal, (_, _) => Reload(), dispatcher);
        debounce.Stop();
        var directory = Path.GetDirectoryName(FilePath);
        if (string.IsNullOrEmpty(directory)) return;
        if (!Directory.Exists(directory))
        {
            // The launcher may create the folder later; check again every few seconds.
            directoryPoll = new DispatcherTimer(TimeSpan.FromSeconds(3), DispatcherPriority.Background, (_, _) =>
            {
                if (!Directory.Exists(directory)) return;
                directoryPoll?.Stop(); directoryPoll = null;
                AttachWatcher(directory, dispatcher);
                Schedule();
            }, dispatcher);
            directoryPoll.Start();
            return;
        }
        AttachWatcher(directory, dispatcher);
    }

    private static void AttachWatcher(string directory, Dispatcher dispatcher)
    {
        try
        {
            var name = Path.GetFileName(FilePath);
            watcher = new FileSystemWatcher(directory) { NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.CreationTime, IncludeSubdirectories = false };
            void Touched(string? file) { if (string.Equals(file, name, StringComparison.OrdinalIgnoreCase)) dispatcher.BeginInvoke(Schedule); }
            watcher.Changed += (_, e) => Touched(e.Name);
            watcher.Created += (_, e) => Touched(e.Name);
            watcher.Deleted += (_, e) => Touched(e.Name);
            watcher.Renamed += (_, e) => { Touched(e.Name); Touched(e.OldName); };
            watcher.Error += (_, _) => dispatcher.BeginInvoke(() => { watcher?.Dispose(); watcher = null; AttachWatcher(directory, dispatcher); Schedule(); });
            watcher.EnableRaisingEvents = true;
        }
        catch { watcher?.Dispose(); watcher = null; }
    }

    private static void Schedule()
    {
        if (debounce == null) return;
        debounce.Stop();
        debounce.Start();
    }

    private static void Reload()
    {
        debounce?.Stop();
        try
        {
            if (!File.Exists(FilePath)) { retries = 0; return; } // Mid-rename or removed: keep the current colours.
            TryLoadFile(); // Invalid / partially written JSON keeps the current colours.
            retries = 0;
        }
        catch (IOException)
        {
            // File is still locked by the writer: try again shortly.
            if (++retries <= 10) Schedule(); else retries = 0;
        }
    }
}
