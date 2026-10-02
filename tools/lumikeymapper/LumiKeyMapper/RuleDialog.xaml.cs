using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using LumiKeyMapper.Core;
using LumiKeyMapper.Services;

namespace LumiKeyMapper;

public partial class RuleDialog : Window
{
    private readonly InputService service;
    private readonly AppSettings settings;
    private readonly MappingRule original;
    public MappingRule? Result { get; private set; }
    public RuleDialog(InputService service, AppSettings settings, MappingRule? rule = null)
    {
        InitializeComponent();
        Height = Math.Min(Height, SystemParameters.WorkArea.Height);
        this.service = service;
        this.settings = settings;
        original = rule ?? new();
        SourcePicker.Service = TargetPicker.Service = service;
        if (rule != null)
        {
            Title = "编辑映射 · LumiKeyMapper";
            Heading.Text = "编辑映射";
            SubHeading.Text = "调整这个按键习惯，保存后立即生效。";
            SourcePicker.Value = rule.Source;
            TargetPicker.Value = rule.Target;
            NameBox.Text = rule.Name;
            ProcessBox.Text = rule.ProcessName;
            TitleBox.Text = rule.TitleContains;
            AppScope.IsChecked = rule.Scope == MappingScope.Application;
            GlobalScope.IsChecked = rule.Scope == MappingScope.Global;
        }
        RefreshWindows();
        service.SetEditing(true);
        SourcePicker.ValueChanged += ClearError;
        TargetPicker.ValueChanged += ClearError;
        Closed += (_,_)=> { service.CancelCapture(); service.SetEditing(false); };
    }
    private void ClearError() => ShowError(null);
    private void ShowError(string? message)
    {
        ErrorText.Text = message ?? "";
        ErrorPanel.Visibility = string.IsNullOrEmpty(message) ? Visibility.Collapsed : Visibility.Visible;
    }
    private void Header_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) try { DragMove(); } catch (InvalidOperationException) { }
    }
    private void Scope_Changed(object sender, RoutedEventArgs e)
    {
        if (AppOptions == null) return;
        var app = AppScope.IsChecked == true;
        AppOptions.Visibility = app ? Visibility.Visible : Visibility.Collapsed;
        ScopeHint.Text = app ? "只在所选应用（可再按窗口标题细分）处于前台时生效，优先于全局规则。" : "在任何前台应用中生效。";
    }
    private void RefreshWindows() => WindowList.ItemsSource = WindowCatalog.List();
    private void RefreshWindows_Click(object sender, RoutedEventArgs e) => RefreshWindows();
    private void WindowList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (WindowList.SelectedItem is WindowEntry window) ProcessBox.Text = window.ProcessName + ".exe";
    }
    private void UseTitle_Click(object sender, RoutedEventArgs e)
    {
        if (WindowList.SelectedItem is WindowEntry window) TitleBox.Text = window.Title;
    }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (SourcePicker.Value is not { } source || TargetPicker.Value is not { } target) { ShowError("请录入原按键和映射按键。"); return; }
        var rule = original with { Source=source, Target=target, Name=NameBox.Text.Trim(), Scope=AppScope.IsChecked == true ? MappingScope.Application : MappingScope.Global, ProcessName=ProcessBox.Text.Trim(), TitleContains=TitleBox.Text.Trim() };
        var error = RuleValidator.Validate(rule,settings.Rules,settings.PauseKey);
        if (error != null) { ShowError(error); return; }
        Result = rule;
        DialogResult = true;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        // DialogResult can only be set on a modal window (offscreen tests construct it without ShowDialog).
        try { DialogResult = false; } catch (InvalidOperationException) { Close(); }
    }
}
