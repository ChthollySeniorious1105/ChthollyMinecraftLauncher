"""Finds functions that mutate shared launcher state (app.ctx.* / app.settings.*) without notifying AppState.

A local setState() only repaints that widget; anything else showing the same data (sidebar account chip,
other tabs, home page) stays stale until something rebuilds the Shell — e.g. switching pages.
Notifiers: app.changed(), app.saveSettings(), notifyListeners(), app.runTask(...) (notifies when done).
Usage: python tool/scan_notify.py lib
"""
import pathlib
import re
import sys

MUT = re.compile(r'\b(?:app|App\.read\(context\)|a)\.(?:ctx\.\w+(?:\.\w+)*\.(?:save|select|add\w*|remove\w*|upsert|delete\w*|pin|rename|move|install\w*|uninstall|set\w*|clear|toggle|scan|load|refresh|import\w*|update)\w*\(|settings\.\w+\s*=(?!=)|ctx\.\w+(?:\.\w+)*\s*=(?!=))')
NOTIFY = re.compile(r'\.changed\(\)|saveSettings\(|notifyListeners\(|runTask\(')
FUNC = re.compile(r'^\s*(?:Future<[^>]*>|void|[A-Z]\w*(?:<[^>]*>)?\??)\s+(_?\w+)\s*\([^;{]*\)\s*(?:async\s*)?\{', re.M)
CLOSURE = re.compile(r'\b(on\w+)\s*:\s*(?:\([^)]*\)|\(\))\s*(?:async\s*)?\{')


def block(src, i):
    depth = 0
    for j in range(i, len(src)):
        if src[j] == '{':
            depth += 1
        elif src[j] == '}':
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
    return src[i:]


for f in sorted(pathlib.Path(sys.argv[1]).rglob('*.dart')):
    if 'i18n' in f.parts:
        continue
    s = f.read_text(encoding='utf-8')
    for rx in (FUNC, CLOSURE):
        for m in rx.finditer(s):
            body = block(s, s.index('{', m.end() - 1))
            if MUT.search(body) and not NOTIFY.search(body):
                line = s[:m.start()].count('\n') + 1
                hit = MUT.search(body).group(0)
                print(f'{f}:{line}: {m.group(1)}  ({hit})')
