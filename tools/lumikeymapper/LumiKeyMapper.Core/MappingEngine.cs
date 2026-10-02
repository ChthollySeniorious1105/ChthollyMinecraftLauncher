namespace LumiKeyMapper.Core;

// A deterministic state machine; all calls belong to the input thread.
public sealed class MappingEngine(Action<OutputSignal> send)
{
    private readonly Dictionary<InputKey, InputKey?> held = [];
    private readonly Dictionary<InputKey, int> outputOwners = [];
    private readonly HashSet<InputKey> physicalDown = [];
    private readonly HashSet<InputKey> passedDown = [];
    private readonly Dictionary<InputKey, int> wheelRemainder = [];
    private MappingRule[] rules = [];
    private WindowContext? context;
    private bool enabled = true;
    private bool suspended;
    public InputKey PauseKey { get; private set; } = InputKey.LeftControl;
    public bool IsPaused { get; private set; }
    public event Action? StateChanged;
    public bool IsPhysicallyDown(InputKey key) => physicalDown.Contains(key);

    public void Configure(IEnumerable<MappingRule> newRules, InputKey pauseKey, bool isEnabled)
    {
        ReleaseAll();
        rules = newRules.Where(r=>r.Enabled).OrderByDescending(r=>r.Scope == MappingScope.Application).ThenByDescending(r=>r.TitleContains.Trim().Length).ToArray();
        PauseKey = pauseKey;
        enabled = isEnabled;
        IsPaused = physicalDown.Contains(pauseKey);
        StateChanged?.Invoke();
    }

    public void Suspend(bool value)
    {
        if (value) ReleaseAll();
        suspended = value;
    }

    public void SetContext(WindowContext value)
    {
        if (context != null && (context.WindowId != value.WindowId || context.IsMapper != value.IsMapper ||
            !string.Equals(context.ProcessName,value.ProcessName,StringComparison.OrdinalIgnoreCase) ||
            rules.Any(r=>r.Scope == MappingScope.Application && r.Matches(context) != r.Matches(value)))) ReleaseAll();
        context = value;
    }

    public bool Process(InputSignal signal, WindowContext window)
    {
        SetContext(window);
        var key = signal.Key;
        var wasDown = physicalDown.Contains(key);
        if (!key.IsPulse)
        {
            if (signal.IsDown) physicalDown.Add(key); else physicalDown.Remove(key);
        }
        if (key == PauseKey)
        {
            if (IsPaused != signal.IsDown)
            {
                IsPaused = signal.IsDown;
                if (IsPaused) ReleaseAll();
                StateChanged?.Invoke();
            }
            return Pass(signal);
        }

        if (!signal.IsDown)
        {
            if (held.Remove(key, out var target))
            {
                if (target.HasValue) Release(target.Value);
                return true;
            }
            // A real target's release must not lift an output still held by a mapping.
            passedDown.Remove(key);
            return outputOwners.ContainsKey(key);
        }
        if (held.TryGetValue(key, out var activeTarget))
        {
            if (activeTarget is { Kind: InputKind.Keyboard } repeat) send(new(repeat, true));
            if (activeTarget is { Kind: InputKind.Wheel } wheel) send(new(wheel, true));
            return true;
        }
        if (!enabled || suspended || IsPaused || window.IsMapper) return Pass(signal);
        // Do not start remapping midway through a physical hold after a focus/config change.
        if (!key.IsPulse && wasDown) return Pass(signal);
        var rule = rules.FirstOrDefault(r=>r.Source == key && r.Matches(window));
        if (rule == null) return Pass(signal);
        if (key.IsPulse)
        {
            if (rule.Target.IsPulse) send(new(rule.Target, true, Math.Abs(signal.Delta)));
            else
            {
                var total = wheelRemainder.GetValueOrDefault(key) + Math.Abs(signal.Delta);
                wheelRemainder[key] = total % 120;
                for (var i = 0; i < total / 120; i++) Tap(rule.Target);
            }
        }
        else
        {
            held[key] = rule.Target;
            if (rule.Target.IsPulse) send(new(rule.Target, true));
            else Press(rule.Target);
        }
        return true;
    }

    private void Press(InputKey key)
    {
        var count = outputOwners.GetValueOrDefault(key);
        outputOwners[key] = count + 1;
        if (count == 0 && !passedDown.Contains(key)) send(new(key, true));
    }
    private void Release(InputKey key)
    {
        if (key.IsPulse || !outputOwners.TryGetValue(key, out var count)) return;
        if (count > 1) outputOwners[key] = count - 1;
        else
        {
            outputOwners.Remove(key);
            if (!passedDown.Contains(key)) send(new(key, false));
        }
    }
    private void Tap(InputKey key)
    {
        if (outputOwners.ContainsKey(key) || passedDown.Contains(key))
        {
            if (key.Kind == InputKind.Keyboard) send(new(key, true));
            return;
        }
        send(new(key, true));
        send(new(key, false));
    }
    public void ReleaseAll()
    {
        foreach (var key in outputOwners.Keys)
            if (!passedDown.Contains(key)) send(new(key, false));
        outputOwners.Clear();
        foreach (var source in held.Keys.ToArray()) held[source] = null;
        wheelRemainder.Clear();
    }

    private bool Pass(InputSignal signal)
    {
        if (!signal.Key.IsPulse)
        {
            if (signal.IsDown) passedDown.Add(signal.Key); else passedDown.Remove(signal.Key);
        }
        return false;
    }
}
