using System.Text.Json.Serialization;

namespace LumiKeyMapper.Core;

public enum InputKind { Keyboard, Mouse, Wheel }
public enum MappingScope { Global, Application }

public readonly record struct InputKey(InputKind Kind, int Code)
{
    public static InputKey LeftControl => new(InputKind.Keyboard, 0xA2);
    [JsonIgnore] public bool IsPulse => Kind == InputKind.Wheel;
    [JsonIgnore] public string Label => KeyCatalog.Label(this);
    [JsonIgnore] public string Category => Kind switch { InputKind.Keyboard => "键盘", InputKind.Mouse => "鼠标", _ => "滚轮" };
    [JsonIgnore] public bool IsValid => Kind switch
    {
        InputKind.Keyboard => Code is >= 8 and <= 254 && Code is not (0x10 or 0x11 or 0x12),
        InputKind.Mouse => Code is >= 1 and <= 5,
        InputKind.Wheel => Code is >= 1 and <= 4,
        _ => false
    };
}

public sealed record MappingRule
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public string Name { get; init; } = "";
    public InputKey Source { get; init; } = new(InputKind.Keyboard, 0x41);
    public InputKey Target { get; init; } = new(InputKind.Keyboard, 0x42);
    public MappingScope Scope { get; init; }
    public string ProcessName { get; init; } = "";
    public string TitleContains { get; init; } = "";
    public bool Enabled { get; init; } = true;
    [JsonIgnore] public string DisplayName => string.IsNullOrWhiteSpace(Name) ? $"{Source.Label} → {Target.Label}" : Name;
    [JsonIgnore] public string ScopeLabel => Scope == MappingScope.Global ? "全局" : NormalizeProcess(ProcessName) + (string.IsNullOrWhiteSpace(TitleContains) ? " · 所有窗口" : $" · {TitleContains}");
    public bool Matches(WindowContext window) => Scope == MappingScope.Global ||
        (string.Equals(NormalizeProcess(ProcessName), NormalizeProcess(window.ProcessName), StringComparison.OrdinalIgnoreCase) &&
         (string.IsNullOrWhiteSpace(TitleContains) || window.Title.Contains(TitleContains, StringComparison.OrdinalIgnoreCase)));
    public static string NormalizeProcess(string name)
    {
        var file = Path.GetFileName((name ?? "").Trim());
        return file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? file[..^4] : file;
    }
}

public sealed record WindowContext(string ProcessName, string Title, long WindowId, bool IsMapper = false);
public readonly record struct InputSignal(InputKey Key, bool IsDown, int Delta = 120);
public readonly record struct OutputSignal(InputKey Key, bool IsDown, int Delta = 120);

public sealed class AppSettings
{
    public int Version { get; set; } = 1;
    public bool Enabled { get; set; } = true;
    public bool CloseToTray { get; set; } = true;
    public InputKey PauseKey { get; set; } = InputKey.LeftControl;
    public List<MappingRule> Rules { get; set; } = [];
}

public static class RuleValidator
{
    public static string? Validate(MappingRule rule, IEnumerable<MappingRule> others, InputKey pauseKey)
    {
        if (!rule.Source.IsValid || !rule.Target.IsValid) return "请先录入有效的原按键和映射按键。";
        if (rule.Source == rule.Target) return "原按键和映射按键不能相同。";
        if (rule.Source == pauseKey) return "此按键已用作临时暂停键，请换一个原按键，或先修改暂停键。";
        if (!Enum.IsDefined(rule.Scope)) return "映射范围无效。";
        if (rule.Scope == MappingScope.Application && string.IsNullOrWhiteSpace(MappingRule.NormalizeProcess(rule.ProcessName))) return "请选择应用窗口，或填写应用的进程名称。";
        if (others.Any(x => x.Id != rule.Id && x.Source == rule.Source && x.Scope == rule.Scope &&
            (rule.Scope == MappingScope.Global || (string.Equals(MappingRule.NormalizeProcess(x.ProcessName), MappingRule.NormalizeProcess(rule.ProcessName), StringComparison.OrdinalIgnoreCase) &&
            string.Equals(x.TitleContains.Trim(), rule.TitleContains.Trim(), StringComparison.OrdinalIgnoreCase))))) return "这个范围内已存在相同原按键的映射，请编辑已有规则。";
        return null;
    }
}

public static class KeyCatalog
{
    private static readonly Dictionary<int, string> Names = new()
    {
        [8]="Backspace",[9]="Tab",[12]="Clear",[13]="Enter",[19]="Pause",[20]="Caps Lock",[27]="Esc",[32]="Space",
        [33]="Page Up",[34]="Page Down",[35]="End",[36]="Home",[37]="←",[38]="↑",[39]="→",[40]="↓",
        [44]="Print Screen",[45]="Insert",[46]="Delete",[91]="左 Win",[92]="右 Win",[93]="菜单",
        [106]="数字键盘 *",[107]="数字键盘 +",[109]="数字键盘 −",[110]="数字键盘 .",[111]="数字键盘 /",
        [144]="Num Lock",[145]="Scroll Lock",[160]="左 Shift",[161]="右 Shift",[162]="左 Ctrl",[163]="右 Ctrl",[164]="左 Alt",[165]="右 Alt",
        [166]="浏览器后退",[167]="浏览器前进",[168]="浏览器刷新",[169]="浏览器停止",[170]="浏览器搜索",[172]="浏览器主页",
        [173]="静音",[174]="音量 −",[175]="音量 +",[176]="下一曲",[177]="上一曲",[178]="媒体停止",[179]="播放 / 暂停",
        [186]="; / :",[187]="= / +",[188]=", / <",[189]="− / _",[190]=". / >",[191]="/ / ?",[192]="` / ~",[219]="[ / {",[220]="\\ / |",[221]="] / }",[222]="' / \"",[226]="OEM 102"
    };
    public static string Label(InputKey key) => key.Kind switch
    {
        InputKind.Mouse => key.Code switch { 1=>"鼠标左键",2=>"鼠标右键",3=>"鼠标中键",4=>"鼠标侧键 1",5=>"鼠标侧键 2",_=>"未知鼠标键" },
        InputKind.Wheel => key.Code switch { 1=>"滚轮 ↑",2=>"滚轮 ↓",3=>"滚轮 ←",4=>"滚轮 →",_=>"未知滚轮" },
        _ when key.Code is >= 48 and <= 57 or >= 65 and <= 90 => ((char)key.Code).ToString(),
        _ when key.Code is >= 112 and <= 135 => $"F{key.Code - 111}",
        _ when key.Code is >= 96 and <= 105 => $"数字键盘 {key.Code - 96}",
        _ => Names.GetValueOrDefault(key.Code, $"键 0x{key.Code:X2}")
    };
    public static IReadOnlyList<InputKey> All { get; } =
        Enumerable.Range(1,5).Select(x=>new InputKey(InputKind.Mouse,x))
        .Concat(Enumerable.Range(1,4).Select(x=>new InputKey(InputKind.Wheel,x)))
        .Concat(Enumerable.Range(65,26).Concat(Enumerable.Range(48,10)).Concat(Enumerable.Range(112,24)).Concat(Names.Keys).Concat(Enumerable.Range(96,10)).Distinct().Select(x=>new InputKey(InputKind.Keyboard,x))).ToArray();
}
