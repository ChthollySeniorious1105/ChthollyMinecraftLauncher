using LumiKeyMapper.Core;
using LumiKeyMapper.Services;
using System.Text.Json;

var suite = new Suite();
suite.Run();
return suite.Failed == 0 ? 0 : 1;

sealed class Suite
{
    public int Failed;
    private int passed;
    private static readonly InputKey A = new(InputKind.Keyboard,65), B = new(InputKind.Keyboard,66), C = new(InputKind.Keyboard,67), D = new(InputKind.Keyboard,68), Ctrl = InputKey.LeftControl;
    private static readonly InputKey Left = new(InputKind.Mouse,1), Right = new(InputKind.Mouse,2), Up = new(InputKind.Wheel,1), Down = new(InputKind.Wheel,2);
    private static readonly WindowContext Notepad = new("notepad","Notes - Notepad",1), Browser = new("browser","Web",2), Own = new("LumiKeyMapper","Lumi",3,true);
    private readonly List<OutputSignal> output = [];
    private MappingEngine engine = null!;
    private static MappingRule Rule(InputKey from,InputKey to,MappingScope scope=MappingScope.Global,string process="",string title="") => new() { Source=from,Target=to,Scope=scope,ProcessName=process,TitleContains=title };
    private void Setup(params MappingRule[] rules) { output.Clear(); engine = new(output.Add); engine.Configure(rules,Ctrl,true); }
    private bool DownKey(InputKey key,WindowContext? window=null,int delta=120) => engine.Process(new(key,true,delta),window??Notepad);
    private bool UpKey(InputKey key,WindowContext? window=null) => engine.Process(new(key,false),window??Notepad);
    private static void Check(bool value,string message="Assertion failed") { if(!value) throw new Exception(message); }
    private void Expect(params OutputSignal[] expected) { Check(output.SequenceEqual(expected),$"Expected [{string.Join(", ",expected)}], got [{string.Join(", ",output)}]"); output.Clear(); }
    private void Test(string name,Action test)
    {
        try { test(); passed++; Console.WriteLine("PASS " + name); }
        catch(Exception ex) { Failed++; Console.WriteLine("FAIL " + name + ": " + ex.Message); }
    }
    public void Run()
    {
        Test("Keyboard hold, repeat and release",()=> { Setup(Rule(A,B)); Check(DownKey(A)); Check(DownKey(A)); Check(UpKey(A)); Expect(new(B,true),new(B,true),new(B,false)); });
        Test("Unmapped input passes through",()=> { Setup(Rule(A,B)); Check(!DownKey(C)); Check(!UpKey(C)); Expect(); });
        Test("Mouse to keyboard preserves hold",()=> { Setup(Rule(Left,B)); Check(DownKey(Left)); Check(UpKey(Left)); Expect(new(B,true),new(B,false)); });
        Test("Keyboard to mouse avoids duplicate mouse down on auto-repeat",()=> { Setup(Rule(A,Left)); DownKey(A); DownKey(A); UpKey(A); Expect(new(Left,true),new(Left,false)); });
        Test("Mouse to mouse",()=> { Setup(Rule(Left,Right)); DownKey(Left); UpKey(Left); Expect(new(Right,true),new(Right,false)); });
        Test("Wheel to keyboard emits taps",()=> { Setup(Rule(Up,B)); Check(DownKey(Up)); Expect(new(B,true),new(B,false)); });
        Test("High-resolution wheel accumulates fractions",()=> { Setup(Rule(Up,B)); DownKey(Up,delta:40); DownKey(Up,delta:40); Expect(); DownKey(Up,delta:40); Expect(new(B,true),new(B,false)); });
        Test("Multi-detent wheel emits correct number of clicks",()=> { Setup(Rule(Up,Left)); DownKey(Up,delta:240); Expect(new(Left,true),new(Left,false),new(Left,true),new(Left,false)); });
        Test("Wheel to wheel preserves magnitude",()=> { Setup(Rule(Up,Down)); DownKey(Up,delta:60); Expect(new OutputSignal(Down,true,60)); });
        Test("Keyboard to wheel repeats on physical auto-repeat",()=> { Setup(Rule(A,Down)); DownKey(A); DownKey(A); UpKey(A); Expect(new(Down,true),new(Down,true)); });
        Test("Application rules override global regardless of order",()=> { Setup(Rule(A,B),Rule(A,C,MappingScope.Application,"NOTEPAD.exe")); DownKey(A); UpKey(A); Expect(new(C,true),new(C,false)); DownKey(A,Browser); UpKey(A,Browser); Expect(new(B,true),new(B,false)); });
        Test("More specific title wins, case insensitive",()=> { Setup(Rule(A,B,MappingScope.Application,"notepad"),Rule(A,C,MappingScope.Application,"notepad","NOTES")); DownKey(A); UpKey(A); Expect(new(C,true),new(C,false)); });
        Test("Wrong application does not match",()=> { Setup(Rule(A,B,MappingScope.Application,"notepad")); Check(!DownKey(A,Browser)); UpKey(A,Browser); Expect(); });
        Test("Title filter limits target windows",()=> { Setup(Rule(A,B,MappingScope.Application,"notepad","unrelated")); Check(!DownKey(A)); UpKey(A); Expect(); });
        Test("Process names containing dots match executable and runtime names",()=> { Setup(Rule(A,B,MappingScope.Application,"my.editor.exe")); var w=new WindowContext("my.editor","Document",7); Check(DownKey(A,w)); UpKey(A,w); Expect(new(B,true),new(B,false)); });
        Test("Irrelevant title changes do not release held output",()=> { Setup(Rule(A,B)); DownKey(A); engine.SetContext(Notepad with { Title="*Notes - Notepad" }); Expect(new OutputSignal(B,true)); UpKey(A); Expect(new OutputSignal(B,false)); });
        Test("Title leaving application filter releases held output",()=> { Setup(Rule(A,B,MappingScope.Application,"notepad","Notes")); DownKey(A); engine.SetContext(Notepad with { Title="Other document" }); Expect(new(B,true),new(B,false)); });
        Test("Own UI remains usable under global mouse remap",()=> { Setup(Rule(Left,Right)); Check(!DownKey(Left,Own)); Check(!UpKey(Left,Own)); Expect(); });
        Test("Disabled rule passes through",()=> { Setup(Rule(A,B) with { Enabled=false }); Check(!DownKey(A)); UpKey(A); Expect(); });
        Test("Pause passes through and resumes after release",()=> { Setup(Rule(A,B)); Check(!DownKey(Ctrl)); Check(engine.IsPaused); Check(!DownKey(A)); Check(!UpKey(A)); UpKey(Ctrl); Check(!engine.IsPaused); DownKey(A); UpKey(A); Expect(new(B,true),new(B,false)); });
        Test("Pause immediately releases active output and swallows old source release",()=> { Setup(Rule(A,B)); DownKey(A); DownKey(Ctrl); Expect(new(B,true),new(B,false)); Check(UpKey(A)); UpKey(Ctrl); Expect(); });
        Test("Releasing pause does not steal a key pressed during pause",()=> { Setup(Rule(A,B)); DownKey(Ctrl); DownKey(A); UpKey(Ctrl); Check(!DownKey(A)); Check(!UpKey(A)); Expect(); DownKey(A); UpKey(A); Expect(new(B,true),new(B,false)); });
        Test("Configurable mouse pause key",()=> { Setup(Rule(A,B)); engine.Configure([Rule(A,B)],Right,true); DownKey(Right); Check(engine.IsPaused); Check(!DownKey(A)); UpKey(A); UpKey(Right); DownKey(A); UpKey(A); Expect(new(B,true),new(B,false)); });
        Test("Focus change releases held targets without leaking source repeat",()=> { Setup(Rule(A,B)); DownKey(A); engine.SetContext(Browser); Expect(new(B,true),new(B,false)); Check(DownKey(A,Browser)); Check(UpKey(A,Browser)); Expect(); });
        Test("Suspending an edit releases active mouse target",()=> { Setup(Rule(A,Left)); DownKey(A); engine.Suspend(true); Expect(new(Left,true),new(Left,false)); UpKey(A); Check(!DownKey(A)); UpKey(A); engine.Suspend(false); DownKey(A); UpKey(A); Expect(new(Left,true),new(Left,false)); });
        Test("Disabling master releases outputs and keeps source release suppressed",()=> { Setup(Rule(A,B)); DownKey(A); engine.Configure([Rule(A,B)],Ctrl,false); Expect(new(B,true),new(B,false)); Check(UpKey(A)); Check(!DownKey(A)); UpKey(A); Expect(); });
        Test("Rule deletion while held releases old output",()=> { Setup(Rule(A,B)); DownKey(A); engine.Configure([],Ctrl,true); Expect(new(B,true),new(B,false)); Check(UpKey(A)); Expect(); });
        Test("Two sources sharing target use reference counts",()=> { Setup(Rule(A,C),Rule(B,C)); DownKey(A); DownKey(B); UpKey(A); Expect(new OutputSignal(C,true)); UpKey(B); Expect(new OutputSignal(C,false)); });
        Test("Physical target hold is preserved when mapping ends",()=> { Setup(Rule(A,B)); DownKey(B); DownKey(A); UpKey(A); Expect(); Check(!UpKey(B)); });
        Test("Physical target release does not prematurely release mapped hold",()=> { Setup(Rule(A,B)); DownKey(A); DownKey(B); Check(UpKey(B)); UpKey(A); Expect(new(B,true),new(B,false)); });
        Test("Mapped source cannot masquerade as a passed-through target",()=> { Setup(Rule(A,B),Rule(B,C)); DownKey(B); DownKey(A); UpKey(A); UpKey(B); Expect(new(C,true),new(B,true),new(B,false),new(C,false)); });
        Test("Wheel tap cannot release a target held by another mapping",()=> { Setup(Rule(A,B),Rule(Up,B)); DownKey(A); DownKey(Up); UpKey(A); Expect(new(B,true),new(B,true),new(B,false)); });
        Test("Shutdown release is idempotent",()=> { Setup(Rule(A,B)); DownKey(A); engine.ReleaseAll(); engine.ReleaseAll(); Expect(new(B,true),new(B,false)); });
        Test("Partial wheel deltas do not cross foreground windows",()=> { Setup(Rule(Up,B)); DownKey(Up,delta:60); DownKey(Up,Browser,60); Expect(); });
        Test("Reserved pause source is rejected",()=> Check(RuleValidator.Validate(Rule(Ctrl,A),[],Ctrl)!=null));
        Test("Identical source and target rejected",()=> Check(RuleValidator.Validate(Rule(A,A),[],Ctrl)!=null));
        Test("Duplicate same-scope source rejected",()=> Check(RuleValidator.Validate(Rule(A,C),[Rule(A,B)],Ctrl)!=null));
        Test("Global and app rules for same source allowed",()=> Check(RuleValidator.Validate(Rule(A,C,MappingScope.Application,"notepad"),[Rule(A,B)],Ctrl)==null));
        Test("Blank application rejected",()=> Check(RuleValidator.Validate(Rule(A,B,MappingScope.Application),[],Ctrl)!=null));
        Test("Unknown input kind rejected",()=> Check(!new InputKey((InputKind)99,1).IsValid));
        Test("Configuration round-trip including unicode",()=> WithFile(path=> { var settings=new AppSettings { PauseKey=Right, Rules=[Rule(A,B,MappingScope.Application,"notepad.exe","文档") with { Name="我的映射" }] }; File.WriteAllText(path,JsonSerializer.Serialize(settings,SettingsStore.JsonOptions)); var read=SettingsStore.Read(path); Check(read.PauseKey==Right && read.Rules[0]==settings.Rules[0]); }));
        Test("Invalid imported pause wheel rejected",()=> WithFile(path=> { File.WriteAllText(path,JsonSerializer.Serialize(new AppSettings { PauseKey=Up },SettingsStore.JsonOptions)); MustThrow(()=>SettingsStore.Read(path)); }));
        Test("Null imported rules rejected",()=> WithFile(path=> { File.WriteAllText(path,"{\"Rules\":null}"); MustThrow(()=>SettingsStore.Read(path)); }));
        Test("Corrupt json rejected without replacing active settings",()=> WithFile(path=> { File.WriteAllText(path,"not json"); MustThrow(()=>SettingsStore.Read(path)); }));
        Test("Future configuration version rejected",()=> WithFile(path=> { File.WriteAllText(path,"{\"Version\":99}"); MustThrow(()=>SettingsStore.Read(path)); }));
        Test("Random hold/focus/pause sequences leave no synthetic key held",()=>
        {
            for(var seed=0;seed<100;seed++)
            {
                var down=new HashSet<InputKey>();
                var random=new Random(seed);
                var e=new MappingEngine(s=> { if(!s.Key.IsPulse) { if(s.IsDown) down.Add(s.Key); else down.Remove(s.Key); } });
                e.Configure([Rule(A,Left),Rule(B,Left),Rule(C,Right)],Ctrl,true);
                var sources=new[]{A,B,C,Ctrl};
                for(var i=0;i<200;i++) e.Process(new(sources[random.Next(4)],random.Next(2)==0),random.Next(5)==0?Browser:Notepad);
                e.ReleaseAll();
                Check(down.Count==0,$"Stuck output at seed {seed}");
            }
        });
        Console.WriteLine($"\n{passed} passed, {Failed} failed");
    }
    private static void WithFile(Action<string> test)
    {
        var path=Path.GetTempFileName();
        try { test(path); } finally { File.Delete(path); }
    }
    private static void MustThrow(Action action)
    {
        try { action(); } catch { return; }
        throw new Exception("Expected a validation error");
    }
}
