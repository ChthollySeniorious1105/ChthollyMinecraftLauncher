using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LumiKeyMapper.Core;
using LumiKeyMapper.Services;
using Forms = System.Windows.Forms;

namespace LumiKeyMapper;

public partial class MainWindow : Window
{
    private readonly SettingsStore store = new();
    private readonly AppSettings settings;
    private readonly InputService input;
    private readonly Forms.NotifyIcon tray;
    private readonly Forms.ToolStripMenuItem trayToggle;
    private MappingRule? deleted;
    private int deletedIndex;
    private bool quitting, paused, updatingPause;
    private readonly bool previewMode;

    public MainWindow(AppSettings? previewSettings = null)
    {
        InitializeComponent();
        previewMode = previewSettings != null;
        settings = previewSettings ?? store.Load();
        input = new InputService();
        input.PauseChanged += value=>Dispatcher.BeginInvoke(()=> { paused=value; UpdateStatus(); });
        input.Error += message=>Dispatcher.BeginInvoke(()=> { settings.Enabled=false; input.Configure(settings); Persist(); UpdateStatus(); ShowNotice(message); });
        PausePicker.Service = input;
        PausePicker.Value = settings.PauseKey;
        PausePicker.ValueChanged += PauseKeyChanged;
        TraySwitch.IsChecked = settings.CloseToTray;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("打开 LumiKeyMapper",null,(_,_)=>Dispatcher.BeginInvoke(ShowFromTray));
        trayToggle = new Forms.ToolStripMenuItem("暂停映射",null,(_,_)=>Dispatcher.BeginInvoke(()=>SetEnabled(!settings.Enabled)));
        menu.Items.Add(trayToggle);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出",null,(_,_)=>Dispatcher.BeginInvoke(Quit));
        tray = new Forms.NotifyIcon { Text="LumiKeyMapper", Icon=CreateTrayIcon(), ContextMenuStrip=menu, Visible=true };
        tray.DoubleClick += (_,_)=>Dispatcher.BeginInvoke(ShowFromTray);
        input.Configure(previewMode ? new AppSettings { Enabled=false } : settings);
        RefreshRules();
        UpdateStatus();
        UpdateTheme();
        ThemeBridge.Changed += OnThemeChanged;
        StateChanged += (_,_)=>UpdateWindowState();
        VersionText.Text = "v" + (typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "1.0.0");
        if (store.LoadWarning != null) ShowNotice(store.LoadWarning);
        Closing += OnClosing;
        Closed += (_,_)=> { ThemeBridge.Changed -= OnThemeChanged; input.Dispose(); tray.Visible=false; tray.Icon?.Dispose(); tray.Dispose(); System.Windows.Application.Current.Shutdown(); };
        System.Windows.Application.Current.SessionEnding += (_,_)=> { quitting=true; input.Dispose(); };
    }
    private static System.Drawing.Icon CreateTrayIcon()
    {
        using var bitmap = new System.Drawing.Bitmap(32,32);
        using var graphics = System.Drawing.Graphics.FromImage(bitmap);
        var accent = ThemeBridge.Current.Accent;
        graphics.Clear(System.Drawing.Color.FromArgb(accent.R,accent.G,accent.B));
        using var font = new System.Drawing.Font("Segoe UI",19,System.Drawing.FontStyle.Bold);
        graphics.DrawString("L",font,System.Drawing.Brushes.White,4,-1);
        var handle = bitmap.GetHicon();
        try { using var icon = System.Drawing.Icon.FromHandle(handle); return (System.Drawing.Icon)icon.Clone(); }
        finally { Native.DestroyIcon(handle); }
    }
    private void OnThemeChanged() => Dispatcher.BeginInvoke(UpdateTheme);
    private void UpdateTheme()
    {
        var theme = ThemeBridge.Current;
        ThemeName.Text = theme.Name + (theme.Dark ? " · 深色" : " · 浅色");
        ThemeSource.Text = ThemeBridge.FromFile ? "来自 " + ThemeBridge.FilePath : "未找到启动器主题文件，正在使用默认配色";
        ThemeSource.ToolTip = ThemeBridge.FilePath;
        UpdateStatus();
    }
    private void UpdateWindowState()
    {
        // A chrome-less maximized window extends past the screen edge by the resize border; pad it back in.
        var frame = SystemParameters.WindowResizeBorderThickness;
        RootFrame.Margin = WindowState == WindowState.Maximized ? new Thickness(frame.Left + 1, frame.Top + 1, frame.Right + 1, frame.Bottom + 1) : new Thickness(0);
        MaximizeButton.Content = WindowState == WindowState.Maximized ? "" : "";
        MaximizeButton.ToolTip = WindowState == WindowState.Maximized ? "向下还原" : "最大化";
    }
    private void Minimize_Click(object sender,RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void Maximize_Click(object sender,RoutedEventArgs e) => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    private void CloseWindow_Click(object sender,RoutedEventArgs e) => Close();
    private void ShowFromTray() { Show(); WindowState=WindowState.Normal; Activate(); }
    private void Quit() { quitting=true; Close(); }
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (!quitting && !previewMode && settings.CloseToTray)
        {
            e.Cancel=true;
            Hide();
            tray.ShowBalloonTip(2000,"LumiKeyMapper","已在系统托盘继续运行。右键托盘图标可以完全退出。",Forms.ToolTipIcon.Info);
        }
    }
    private void Persist()
    {
        if (previewMode) return;
        try { store.Save(settings); SaveStatus.Text="配置已保存到本机"; }
        catch (Exception ex) { SaveStatus.Text="配置保存失败"; ShowNotice("规则已在本次运行生效，但无法保存：" + ex.Message); }
    }
    private void Apply() { if (!previewMode) input.Configure(settings); Persist(); RefreshRules(); UpdateStatus(); }
    private void SetEnabled(bool value) { settings.Enabled=value; Apply(); }
    private void UpdateStatus()
    {
        if (settings == null || trayToggle == null) return;
        MasterSwitch.IsChecked=settings.Enabled;
        MasterLabel.Text=settings.Enabled ? "映射已开启" : "映射已关闭";
        PauseLabel.Text=settings.PauseKey.Label;
        StatusTitle.Text=!settings.Enabled ? "映射已停用" : paused ? "临时暂停中" : "映射正在运行";
        PauseHint.Text=paused && settings.Enabled ? "松开后自动恢复映射" : "临时暂停，松开后自动恢复";
        StatusDot.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, !settings.Enabled ? "MutedBrush" : paused ? "WarningBrush" : "SuccessBrush");
        StatusPill.SetResourceReference(Border.BackgroundProperty, !settings.Enabled ? "FieldBrush" : paused ? "WarningSoftBrush" : "Accent2SoftBrush");
        trayToggle.Text=settings.Enabled ? "暂停映射" : "启用映射";
        tray.Text="LumiKeyMapper · " + (!settings.Enabled ? "已停用" : paused ? "临时暂停" : "运行中");
    }
    private void RefreshRules()
    {
        if (settings == null) return;
        var query = SearchBox.Text.Trim();
        var visible = settings.Rules.Where(rule=>
            (ScopeFilter.SelectedIndex switch { 1=>rule.Scope==MappingScope.Global,2=>rule.Scope==MappingScope.Application,3=>!rule.Enabled,_=>true }) &&
            (query.Length==0 || $"{rule.DisplayName} {rule.Source.Label} {rule.Target.Label} {rule.ScopeLabel}".Contains(query,StringComparison.OrdinalIgnoreCase))).ToArray();
        RuleList.ItemsSource=visible;
        EmptyState.Visibility=visible.Length==0 ? Visibility.Visible : Visibility.Collapsed;
        EmptyTitle.Text=settings.Rules.Count==0 ? "从第一个映射开始" : "没有找到匹配的规则";
        EmptyDescription.Text=settings.Rules.Count==0 ? "比如，把鼠标侧键变成更顺手的 Enter。" : "试试其他关键词，或切换范围筛选。";
        EmptyAddButton.Visibility=settings.Rules.Count==0 ? Visibility.Visible : Visibility.Collapsed;
        TotalCountRun.Text=settings.Rules.Count.ToString();
        EnabledCountRun.Text=settings.Rules.Count(x=>x.Enabled).ToString();
        AppsCountRun.Text=settings.Rules.Where(x=>x.Scope==MappingScope.Application).Select(x=>MappingRule.NormalizeProcess(x.ProcessName)).Distinct(StringComparer.OrdinalIgnoreCase).Count().ToString();
    }
    private void Add_Click(object sender,RoutedEventArgs e) => EditRule(null);
    private void EditRule(MappingRule? rule)
    {
        var dialog = new RuleDialog(input,settings,rule) { Owner=this };
        bool? accepted;
        Scrim.Visibility=Visibility.Visible;
        try { accepted=dialog.ShowDialog(); }
        finally { Scrim.Visibility=Visibility.Collapsed; }
        if (accepted==true && dialog.Result is { } result)
        {
            var index=settings.Rules.FindIndex(x=>x.Id==result.Id);
            if (index>=0) settings.Rules[index]=result; else settings.Rules.Add(result);
            Apply();
        }
    }
    private Guid SenderId(object sender) => (Guid)((FrameworkElement)sender).Tag;
    private void Edit_Click(object sender,RoutedEventArgs e) => EditRule(settings.Rules.First(x=>x.Id==SenderId(sender)));
    private void Delete_Click(object sender,RoutedEventArgs e)
    {
        deletedIndex=settings.Rules.FindIndex(x=>x.Id==SenderId(sender));
        if (deletedIndex<0) return;
        deleted=settings.Rules[deletedIndex];
        settings.Rules.RemoveAt(deletedIndex);
        Apply();
        ShowNotice($"已删除「{deleted.DisplayName}」",true);
    }
    private void Undo_Click(object sender,RoutedEventArgs e)
    {
        if (deleted == null) return;
        var error=RuleValidator.Validate(deleted,settings.Rules,settings.PauseKey);
        if (error!=null) { ShowNotice("无法撤销："+error); return; }
        settings.Rules.Insert(Math.Min(deletedIndex,settings.Rules.Count),deleted);
        deleted=null;
        Apply();
        ShowNotice("已恢复删除的规则。");
    }
    private void RuleToggle_Click(object sender,RoutedEventArgs e)
    {
        var index=settings.Rules.FindIndex(x=>x.Id==SenderId(sender));
        settings.Rules[index]=settings.Rules[index] with { Enabled=((CheckBox)sender).IsChecked==true };
        Apply();
    }
    private void MasterSwitch_Click(object sender,RoutedEventArgs e) => SetEnabled(MasterSwitch.IsChecked==true);
    private void TraySwitch_Click(object sender,RoutedEventArgs e) { settings.CloseToTray=TraySwitch.IsChecked==true; Persist(); }
    private void Filter_Changed(object sender,SelectionChangedEventArgs e) => RefreshRules();
    private void Search_Changed(object sender,TextChangedEventArgs e) => RefreshRules();
    private void SelectPage(int page)
    {
        RulesPage.Visibility=page==0 ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility=page==1 ? Visibility.Visible : Visibility.Collapsed;
        HelpPage.Visibility=page==2 ? Visibility.Visible : Visibility.Collapsed;
        var nav=new[] { RulesNav,SettingsNav,HelpNav };
        for(var i=0;i<nav.Length;i++) nav[i].Tag=i==page ? "selected" : null;
    }
    private void RulesNav_Click(object sender,RoutedEventArgs e) => SelectPage(0);
    private void SettingsNav_Click(object sender,RoutedEventArgs e) => SelectPage(1);
    private void HelpNav_Click(object sender,RoutedEventArgs e) => SelectPage(2);
    private void PauseKeyChanged()
    {
        if (updatingPause || PausePicker.Value is not { } key) return;
        if (settings.Rules.Any(x=>x.Source==key))
        {
            ShowNotice("该键已用作映射原按键，请先修改或删除对应规则。");
            updatingPause=true; PausePicker.Value=settings.PauseKey; updatingPause=false;
            return;
        }
        settings.PauseKey=key;
        Apply();
    }
    private void ResetPause_Click(object sender,RoutedEventArgs e) { PausePicker.Value=InputKey.LeftControl; PauseKeyChanged(); }
    private void Import_Click(object sender,RoutedEventArgs e)
    {
        var dialog=new Microsoft.Win32.OpenFileDialog { Filter="Lumi 配置 (*.json)|*.json",Title="导入 LumiKeyMapper 配置" };
        input.SetEditing(true);
        try
        {
            if (dialog.ShowDialog(this)!=true) return;
            var imported=SettingsStore.Read(dialog.FileName);
            if (MessageBox.Show(this,$"将用导入的 {imported.Rules.Count} 条规则替换现有 {settings.Rules.Count} 条规则。是否继续？","导入配置",MessageBoxButton.OKCancel,MessageBoxImage.Question)!=MessageBoxResult.OK) return;
            Directory.CreateDirectory(store.DirectoryPath);
            File.WriteAllText(Path.Combine(store.DirectoryPath,"before-import-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+".json"),JsonSerializer.Serialize(settings,SettingsStore.JsonOptions));
            settings.Rules=imported.Rules;
            settings.PauseKey=imported.PauseKey;
            settings.CloseToTray=imported.CloseToTray;
            settings.Enabled=imported.Enabled;
            updatingPause=true; PausePicker.Value=settings.PauseKey; updatingPause=false;
            TraySwitch.IsChecked=settings.CloseToTray;
            deleted=null;
            Apply();
            ShowNotice("配置已导入，原配置已自动备份到配置文件夹。");
        }
        catch(Exception ex) { ShowNotice("导入失败："+ex.Message); }
        finally { input.SetEditing(false); }
    }
    private void Export_Click(object sender,RoutedEventArgs e)
    {
        var dialog=new Microsoft.Win32.SaveFileDialog { Filter="Lumi 配置 (*.json)|*.json",FileName="LumiKeyMapper-backup.json",Title="导出配置" };
        input.SetEditing(true);
        try { if(dialog.ShowDialog(this)==true) { File.WriteAllText(dialog.FileName,JsonSerializer.Serialize(settings,SettingsStore.JsonOptions)); ShowNotice("配置已导出。"); } }
        catch(Exception ex) { ShowNotice("导出失败："+ex.Message); }
        finally { input.SetEditing(false); }
    }
    private void OpenFolder_Click(object sender,RoutedEventArgs e)
    {
        try { Directory.CreateDirectory(store.DirectoryPath); Process.Start(new ProcessStartInfo(store.DirectoryPath) { UseShellExecute=true }); }
        catch(Exception ex) { ShowNotice("无法打开文件夹："+ex.Message); }
    }
    private void ShowNotice(string text,bool undo=false) { NoticeText.Text=text; UndoButton.Visibility=undo ? Visibility.Visible : Visibility.Collapsed; NoticeBar.Visibility=Visibility.Visible; }
    private void DismissNotice_Click(object sender,RoutedEventArgs e) => NoticeBar.Visibility=Visibility.Collapsed;
}
