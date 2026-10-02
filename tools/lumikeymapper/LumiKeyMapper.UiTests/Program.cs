using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LumiKeyMapper;
using LumiKeyMapper.Controls;
using LumiKeyMapper.Core;
using LumiKeyMapper.Services;

internal static class Program
{
    private const string DarkTheme = """
        { "id": "midnight", "name": "午夜", "version": "1", "dark": true,
          "bg": "#111318", "surface": "#1a1d24", "panel": "#171a20", "text": "#e6e8ee", "muted": "#8b93a3",
          "line": "#2a2f39", "field": "#222631", "accent": "#7aa2f7", "accent2": "#9ece6a", "onAccent": "#0f1117",
          "paper": "#1a1d24", "ink": "#e6e8ee", "art": ["a.png", "b.png"], "unknownField": { "nested": 1 } }
        """;
    private static int checks, renders;

    [STAThread]
    private static int Main(string[] args)
    {
        var output = args.Length > 0 ? Path.GetFullPath(args[0]) : Path.GetFullPath("artifacts");
        Directory.CreateDirectory(output);
        var app = new App();
        app.InitializeComponent();
        ThemeBridge.Apply(ThemePalette.Light);
        var settings = new AppSettings { Rules = [
            new() { Source=new(InputKind.Mouse,4),Target=new(InputKind.Keyboard,13),Name="一键确认" },
            new() { Source=new(InputKind.Keyboard,0x14),Target=new(InputKind.Keyboard,27),Name="顺手退出",Scope=MappingScope.Application,ProcessName="Code.exe" },
            new() { Source=new(InputKind.Wheel,1),Target=new(InputKind.Keyboard,33),Name="阅读翻页",Scope=MappingScope.Application,ProcessName="msedge.exe",TitleContains="文档",Enabled=false },
            new() { Source=new(InputKind.Keyboard,0x70),Target=new(InputKind.Mouse,3),Scope=MappingScope.Global }
        ] };
        var window = new MainWindow(settings);
        try
        {
            ThemeTests(output);

            Snapshot(window,1120,700,Path.Combine(output,"main.png"));
            Check(Items(window)==4,"rule list binds");
            ((TextBox)window.FindName("SearchBox")).Text="Code";
            Check(Items(window)==1,"search filters by process");
            ((TextBox)window.FindName("SearchBox")).Text="";
            ((ComboBox)window.FindName("ScopeFilter")).SelectedIndex=3;
            Check(Items(window)==1,"disabled filter");
            ((ComboBox)window.FindName("ScopeFilter")).SelectedIndex=2;
            Check(Items(window)==2,"application filter");
            ((ComboBox)window.FindName("ScopeFilter")).SelectedIndex=0;
            Check(((TextBlock)window.FindName("StatusTitle")).Text=="映射正在运行","status bar shows running state");

            Click(window,"SettingsNav");
            Snapshot(window,1120,700,Path.Combine(output,"settings.png"));
            Check(((FrameworkElement)window.FindName("SettingsPage")).Visibility==Visibility.Visible,"settings navigation");
            Check((string?)((Button)window.FindName("SettingsNav")).Tag=="selected" && ((Button)window.FindName("RulesNav")).Tag==null,"nav rail selection");
            Click(window,"HelpNav");
            Snapshot(window,1120,700,Path.Combine(output,"help.png"));
            Check(((FrameworkElement)window.FindName("HelpPage")).Visibility==Visibility.Visible,"help navigation");
            Click(window,"RulesNav");

            using var service = new InputService();
            service.Configure(new() { Enabled=false });
            var dialog = new RuleDialog(service,settings,settings.Rules[1]);
            Snapshot(dialog,680,780,Path.Combine(output,"editor.png"));
            Check(((FrameworkElement)dialog.FindName("AppOptions")).Visibility==Visibility.Visible,"application editor");
            dialog.Close();

            var create = new RuleDialog(service,settings);
            var source = (InputPicker)create.FindName("SourcePicker");
            source.PreviewRecording();
            Snapshot(create,680,780,Path.Combine(output,"editor-recording.png"));
            Check(source.IsRecording && ((FrameworkElement)create.FindName("AppOptions")).Visibility==Visibility.Collapsed,"new rule editor recording state");
            source.Value=settings.Rules[0].Source;
            ((InputPicker)create.FindName("TargetPicker")).Value=new(InputKind.Keyboard,0x41);
            ((Button)create.FindName("SaveButton")).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(((TextBlock)create.FindName("ErrorText")).Text.Contains("已存在"),"duplicate source rejected");
            create.Close();

            // Dark theme applied live to the already-built window.
            ThemeBridge.ApplyJson(DarkTheme);
            Pump();
            Snapshot(window,1120,700,Path.Combine(output,"main-dark.png"));
            Check(((SolidColorBrush)window.FindResource("PanelBrush")).Color==Color.FromRgb(0x17,0x1a,0x20),"live dark theme reaches window resources");
            var darkDialog = new RuleDialog(service,settings,settings.Rules[1]);
            Snapshot(darkDialog,680,780,Path.Combine(output,"editor-dark.png"));
            darkDialog.Close();
            Click(window,"SettingsNav");
            Snapshot(window,1120,900,Path.Combine(output,"settings-dark.png"));
            Click(window,"RulesNav");

            settings.Rules.Clear();
            ((TextBox)window.FindName("SearchBox")).Text="none";
            Check(((FrameworkElement)window.FindName("EmptyState")).Visibility==Visibility.Visible,"empty state");
            ((TextBox)window.FindName("SearchBox")).Text="";
            Snapshot(window,900,600,Path.Combine(output,"empty-minimum-dark.png"));
            ThemeBridge.Apply(ThemePalette.Light);
            Pump();
            Snapshot(window,900,600,Path.Combine(output,"empty-minimum.png"));
            Console.WriteLine($"PASS {checks} UI checks and {renders} offscreen WPF renders; input hooks installed successfully.");
            return 0;
        }
        catch(Exception ex) { Console.Error.WriteLine(ex); return 1; }
        finally { window.Close(); ThemeBridge.Stop(); }
    }

    private static void ThemeTests(string output)
    {
        var parsed = ThemeBridge.Parse(DarkTheme);
        Check(parsed is { Dark: true, Name: "午夜" } && parsed.Accent==Color.FromRgb(0x7a,0xa2,0xf7),"theme JSON parses (unknown fields ignored)");
        var partial = ThemeBridge.Parse("""{ "accent": "#ff8800" }""");
        Check(partial != null && partial.Accent==Color.FromRgb(0xff,0x88,0) && partial.Bg==ThemePalette.Light.Bg,"partial theme falls back to defaults");
        ThemeBridge.Apply(ThemePalette.Light);
        Check(!ThemeBridge.ApplyJson("{ \"accent\": \"#ff00") && ThemeBridge.Current.Accent==ThemePalette.Light.Accent,"invalid theme JSON keeps current colours");

        // File watching: launcher writes theme.json.tmp then renames it over theme.json.
        var folder = Path.Combine(output,"theme-watch");
        Directory.CreateDirectory(folder);
        var file = Path.Combine(folder,"theme.json");
        File.WriteAllText(file,"""{ "dark": false, "accent": "#112233" }""");
        Environment.SetEnvironmentVariable(ThemeBridge.EnvironmentVariable,file);
        ThemeBridge.Start();
        Check(ThemeBridge.FromFile && ThemeBridge.Current.Accent==Color.FromRgb(0x11,0x22,0x33),"CML_THEME_FILE is loaded on start");
        File.WriteAllText(file+".tmp",DarkTheme);
        File.Move(file+".tmp",file,true);
        Check(WaitFor(()=>ThemeBridge.Current.Dark),"theme file rename is picked up live");
        File.WriteAllText(file,"{ \"dark\": false, \"acc");
        Pump(600);
        Check(ThemeBridge.Current.Dark && ThemeBridge.Current.Name=="午夜","partial write keeps current colours");
        ThemeBridge.Stop();
        Environment.SetEnvironmentVariable(ThemeBridge.EnvironmentVariable,null);
        Directory.Delete(folder,true);
        ThemeBridge.Apply(ThemePalette.Light);
    }

    private static int Items(Window window) => ((ItemsControl)window.FindName("RuleList")).Items.Count;
    private static void Click(Window window,string name) => ((Button)window.FindName(name)).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    private static bool WaitFor(Func<bool> condition,int milliseconds=3000)
    {
        var until = DateTime.UtcNow.AddMilliseconds(milliseconds);
        while (DateTime.UtcNow < until) { if (condition()) return true; Pump(50); }
        return condition();
    }
    private static void Pump(int milliseconds=0)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(TimeSpan.FromMilliseconds(Math.Max(1,milliseconds)),DispatcherPriority.Background,(s,_)=> { ((DispatcherTimer)s!).Stop(); frame.Continue=false; },Dispatcher.CurrentDispatcher);
        timer.Start();
        Dispatcher.PushFrame(frame);
    }
    private static void Check(bool value,string name)
    {
        if(!value) throw new Exception("UI check failed: "+name);
        checks++;
        Console.WriteLine("PASS "+name);
    }
    private static void Snapshot(Window window,int width,int height,string path)
    {
        var root = (FrameworkElement)window.Content;
        root.Measure(new Size(width,height));
        root.Arrange(new Rect(0,0,width,height));
        root.UpdateLayout();
        Pump();
        root.UpdateLayout();
        var image = new RenderTargetBitmap(width,height,96,96,PixelFormats.Pbgra32);
        var backdrop = new DrawingVisual();
        using(var drawing = backdrop.RenderOpen()) drawing.DrawRectangle((Brush)Application.Current.Resources["BgBrush"],null,new Rect(0,0,width,height));
        image.Render(backdrop);
        image.Render(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = File.Create(path);
        encoder.Save(stream);
        renders++;
        Console.WriteLine("Rendered "+Path.GetFileName(path));
    }
}
