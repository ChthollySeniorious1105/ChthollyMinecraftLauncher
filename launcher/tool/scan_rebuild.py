"""Heuristic scan for UI handlers that change state but never trigger a rebuild.

For every handler closure (onPressed / onTap / onChanged / onSelected / onSelectionChanged / onSubmitted …)
in lib/, prints those whose body mutates something (assignment, app/ctx/settings call, await) but contains
no rebuild trigger (setState, saveSettings, changed(), notifyListeners, _load/_refresh/_reload …).
Usage: python tool/scan_rebuild.py lib
"""
import pathlib
import re
import sys

HANDLER = re.compile(r'\b(on(?:Pressed|Tap|Changed|Selected|SelectionChanged|Submitted|ChangeEnd|LongPress|DoubleTap|Accept|DragDone|Toggle|Dismissed))\s*:\s*')
REFRESH = re.compile(r'setState|saveSettings|\.changed\(\)|notifyListeners|_load\w*\(|_refresh\w*\(|_reload\w*\(|_scan\w*\(|markNeedsBuild|Navigator\.pop|\.value\s*=|widget\.on\w+|onChanged\(|onSelected\(|refresh\(|reload\(')
MUTATE = re.compile(r'(?<![=!<>])=(?![=>])|\bawait\b|\.(add|remove|insert|clear|select|toggle|delete|save|set\w*|upsert|pin|rename|move|install|uninstall|start|stop)\w*\(')
PURE = re.compile(r'^\s*(?:\(\)\s*(?:async\s*)?=>\s*)?(?:show\w*Dialog|showDialog|launchUrl|toast|Process\.(?:run|start)|openFolder|_open\w*|copy\w*|Clipboard)')


def closure(src, i):
    """Text of the closure / expression starting at i (up to the matching bracket or the end of the argument)."""
    depth = 0
    j = i
    while j < len(src):
        c = src[j]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                return src[i:j]
            depth -= 1
            if depth == 0 and c == '}' and src[i:j].lstrip().startswith(('(', 'async', '()')) and '{' in src[i:j + 1]:
                return src[i:j + 1]
        elif c == ',' and depth == 0:
            return src[i:j]
        j += 1
    return src[i:]


for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.dart')):
    if 'i18n' in f.parts:
        continue
    s = f.read_text(encoding='utf-8')
    for m in HANDLER.finditer(s):
        body = closure(s, m.end())
        b = body.strip()
        if not b or b == 'null' or re.fullmatch(r'[\w.]+', b):  # tear-offs are checked where defined
            continue
        if PURE.match(b) or REFRESH.search(body) or not MUTATE.search(body):
            continue
        line = s[:m.start()].count('\n') + 1
        print(f'{f}:{line}: {m.group(1)}: {" ".join(b.split())[:150]}')
