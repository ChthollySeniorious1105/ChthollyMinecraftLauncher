using System.Windows;
using LumiKeyMapper.Services;

namespace LumiKeyMapper;

public partial class App : System.Windows.Application
{
    private Mutex? instanceMutex;
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instanceMutex = new Mutex(true, @"Local\LumiKeyMapper.Desktop", out var first);
        if (!first)
        {
            MessageBox.Show("LumiKeyMapper 已在运行，请从系统托盘打开。","LumiKeyMapper");
            Shutdown();
            return;
        }
        try { ThemeBridge.Start(); }
        catch { ThemeBridge.Apply(ThemePalette.Light); }
        try
        {
            var window = new MainWindow();
            MainWindow = window;
            window.Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"启动失败：{ex.Message}","LumiKeyMapper",MessageBoxButton.OK,MessageBoxImage.Error);
            Shutdown(1);
        }
    }
    protected override void OnExit(ExitEventArgs e)
    {
        ThemeBridge.Stop();
        instanceMutex?.Dispose();
        base.OnExit(e);
    }
}
