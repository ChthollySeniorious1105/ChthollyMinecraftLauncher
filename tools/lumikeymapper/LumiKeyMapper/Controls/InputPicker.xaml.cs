using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using LumiKeyMapper.Core;
using LumiKeyMapper.Services;

namespace LumiKeyMapper.Controls;

public partial class InputPicker : UserControl
{
    private const string Empty = "未设置";
    private InputKey? value;
    private readonly Storyboard pulse;
    public InputService? Service { get; set; }
    private bool allowWheel = true;
    public bool AllowWheel { get => allowWheel; set { allowWheel = value; LoadItems(); if (!IsRecording) ShowIdle(null); } }
    public bool IsRecording { get; private set; }
    /// <summary>Height of the capture area (default 132).</summary>
    public double AreaHeight { get => RecordButton.Height; set => RecordButton.Height = value; }
    public event Action? ValueChanged;
    public InputKey? Value
    {
        get => value;
        set
        {
            this.value = value;
            KeyList.SelectedItem = value;
            if (!IsRecording) ShowIdle(null);
        }
    }
    public InputPicker()
    {
        InitializeComponent();
        pulse = (Storyboard)Resources["Pulse"];
        LoadItems();
        ShowIdle(null);
    }
    private void LoadItems()
    {
        KeyList.ItemsSource = KeyCatalog.All.Where(k=>allowWheel || !k.IsPulse).ToArray();
        KeyList.SelectedItem = value;
    }
    /// <summary>Segoe Fluent Icons glyph for a key's device.</summary>
    public static string Glyph(InputKey key) => key.Kind switch
    {
        InputKind.Mouse => "\uE962",
        InputKind.Wheel => key.Code switch { 1=>"\uE70E",2=>"\uE70D",3=>"\uE76B",_=>"\uE76C" },
        _ => "\uE765"
    };
    private void ShowIdle(string? hint)
    {
        SetRecording(false);
        KeyLabel.Text = value?.Label ?? Empty;
        KeyLabel.SetResourceReference(TextBlock.ForegroundProperty, value.HasValue ? "TextBrush" : "MutedBrush");
        KeyLabel.FontWeight = value.HasValue ? FontWeights.SemiBold : FontWeights.Normal;
        KindIcon.Text = value.HasValue ? Glyph(value.Value) : "\uE765";
        StateText.Text = value.HasValue ? value.Value.Category : "点击录入";
        RecordHint.Text = hint ?? (value.HasValue ? "点击重新录入" : AllowWheel ? "按键 · 鼠标按键 · 滚轮" : "键盘键或鼠标按键");
    }
    private void SetRecording(bool recording)
    {
        IsRecording = recording;
        RecordButton.Tag = recording ? "recording" : null;
        Dot.SetResourceReference(Shape.FillProperty, recording ? "AccentBrush" : value.HasValue ? "Accent2Brush" : "KeyCapEdgeBrush");
        StateText.SetResourceReference(TextBlock.ForegroundProperty, recording ? "AccentBrush" : "MutedBrush");
        if (recording) { if (IsLoaded) pulse.Begin(this, true); else Ring.Opacity = 0.8; }
        else { pulse.Stop(this); Ring.Opacity = 0; Dot.Opacity = 1; }
    }
    /// <summary>Shows the recording visuals without starting a capture (used by offscreen render tests).</summary>
    public void PreviewRecording() => EnterRecording();
    private void EnterRecording()
    {
        SetRecording(true);
        StateText.Text = "正在录入";
        KeyLabel.Text = "请按下…";
        KeyLabel.SetResourceReference(TextBlock.ForegroundProperty, "AccentBrush");
        KeyLabel.FontWeight = FontWeights.SemiBold;
        RecordHint.Text = AllowWheel ? "按下并松开一个键、点击鼠标或滚动滚轮" : "按下并松开键盘键或鼠标按键";
    }
    private void Record_Click(object sender, RoutedEventArgs e)
    {
        if (Service == null) return;
        EnterRecording();
        Service.Capture(key=>Dispatcher.BeginInvoke(()=>
        {
            if (key.HasValue && (AllowWheel || !key.Value.IsPulse))
            {
                IsRecording = false;
                Value = key;
                ShowIdle("已录入 · 点击可重新录入");
                ValueChanged?.Invoke();
            }
            else ShowIdle(key.HasValue ? "暂停键需要能够按住，请选择键盘或鼠标键" : "录入已取消 · 点击重试");
        }));
    }
    private void KeyList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (KeyList.SelectedItem is InputKey key && key != value)
        {
            Value = key;
            ValueChanged?.Invoke();
        }
    }
}
