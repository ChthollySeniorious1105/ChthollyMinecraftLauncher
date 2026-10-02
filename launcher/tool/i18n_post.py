"""Post-pass after i18n_wrap: routes core-produced text through trCore and cleans double wraps."""
import glob
import re
from pathlib import Path

BS = chr(92)
SUBS = [
    # context.tr(trGlobal('x'), [args]) / context.tr(trGlobal('x')) → trGlobal('x', [args])
    (re.compile(r"context\.tr\(trGlobal\(('(?:[^'" + BS + BS + "]|" + BS + BS + ".)*')\)(, \[)"), r"trGlobal(\1\2"),
    (re.compile(r"context\.tr\(trGlobal\(('(?:[^'" + BS + BS + "]|" + BS + BS + ".)*')\)\)"), r"trGlobal(\1)"),
    # core-produced strings
    (re.compile(r"'\$\{t\.detail\}"), "'${trCore(t.detail)}"),
    (re.compile(r"\$\{entry\.typeLabel\}"), "${trCore(entry.typeLabel)}"),
    (re.compile(r"Pill\(w\.gameModeLabel,"), "Pill(trCore(w.gameModeLabel),"),
    (re.compile(r"\$\{w\.gameModeLabel\}"), "${trCore(w.gameModeLabel)}"),
    (re.compile(r"'\$\{w\.location\}  ·  "), "'${trCore(w.location)}  ·  "),
    (re.compile(r"Text\('\$\{e\.key\} \$\{e\.value\}'\)"), "Text('${trCore(e.key)} ${e.value}')"),
    (re.compile(r"Text\(n\.text, style"), "Text(trCore(n.text), style"),
    (re.compile(r"\[target\.label\]"), "[trCore(target.label)]"),
    (re.compile(r"\[widget\.type\.label\]"), "[trCore(widget.type.label)]"),
    (re.compile(r"Text\(x\.label\)"), "Text(trCore(x.label))"),
    (re.compile(r"Text\(d\.label\)"), "Text(trCore(d.label))"),
    (re.compile(r"Text\(s\.label\)"), "Text(trCore(s.label))"),
    (re.compile(r"Text\(m\.label\)"), "Text(trCore(m.label))"),
    (re.compile(r"Text\(th\.name\)"), "Text(trCore(th.name))"),
    (re.compile(r"Text\(r\.label\)"), "Text(trCore(r.label))"),
    (re.compile(r"Text\(f\.label\)"), "Text(trCore(f.label))"),
    (re.compile(r"Text\(trGlobal\(f\.label\)\)"), "Text(trCore(f.label))"),
    (re.compile(r"Text\(context\.tr\(f\.label\)\)"), "Text(trCore(f.label))"),
    (re.compile(r"Text\(g\.game\.name,"), "Text(trCore(g.game.name),"),
    (re.compile(r"'\$\{w\.version \?\? '未知版本'\}"), "'${w.version ?? trGlobal('未知版本')}"),
]

for f in glob.glob('lib/**/*.dart', recursive=True):
    if 'i18n' in f:
        continue
    s = Path(f).read_text(encoding='utf-8')
    o = s
    for pat, rep in SUBS:
        s = pat.sub(rep, s)
    if s != o:
        Path(f).write_text(s, encoding='utf-8')
        print('patched', f)

# errText: translate core exception messages
st = Path('lib/state.dart')
s = st.read_text(encoding='utf-8')
s = s.replace("String errText(Object e) => e is CmlException ? e.message : '$e';",
              "String errText(Object e) => e is CmlException ? trCore(e.message) : '$e';")
st.write_text(s, encoding='utf-8')
