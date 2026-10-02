"""Wraps every Chinese string literal used as UI text in the launcher with a translation call.

Rules:
  * literal inside a widget build context → context.tr('…') (with {0} placeholders for interpolations)
  * `const` widgets that contain a wrapped literal lose their `const`
  * already wrapped strings (context.tr / translate / trGlobal) are left alone
Writes tool/strings_zh.txt (one unique key per line) for the English table.
"""
import re
import glob
from pathlib import Path

CJK = re.compile(r'[一-鿿（-？、-】]')
# single-quoted Dart string literal (no raw strings)
LIT = re.compile(r"(?<![r\w])'((?:[^'\\\n]|\\.)*)'")

keys = []


def interp_to_template(lit):
    """'共 ${a.length} 个 $b' → ('共 {0} 个 {1}', ['a.length', 'b'])"""
    args = []
    out = []
    i = 0
    while i < len(lit):
        if lit[i] == '\\':
            out.append(lit[i:i + 2]); i += 2; continue
        if lit[i] == '$':
            if i + 1 < len(lit) and lit[i + 1] == '{':
                depth = 0; j = i + 1
                while j < len(lit):
                    if lit[j] == '{': depth += 1
                    elif lit[j] == '}':
                        depth -= 1
                        if depth == 0: break
                    j += 1
                args.append(lit[i + 2:j]); out.append('{%d}' % (len(args) - 1)); i = j + 1; continue
            m = re.match(r'\$([A-Za-z_]\w*)', lit[i:])
            if m:
                args.append(m.group(1)); out.append('{%d}' % (len(args) - 1)); i += len(m.group(0)); continue
        out.append(lit[i]); i += 1
    return ''.join(out), args


SKIP_LINE = re.compile(r"(^\s*//|^\s*///|^import |context\.tr\(|translate\(|trGlobal\(|RegExp\(|\.replaceAll\(|throw |CmlException)")

for f in glob.glob('lib/**/*.dart', recursive=True):
    if 'i18n' in f:
        continue
    src = Path(f).read_text(encoding='utf-8')
    lines = src.split('\n')
    changed = False
    for n, line in enumerate(lines):
        if SKIP_LINE.search(line):
            continue
        def sub(m):
            global changed
            lit = m.group(1)
            if not CJK.search(lit):
                return m.group(0)
            tmpl, args = interp_to_template(lit)
            keys.append(tmpl)
            a = '' if not args else ', [' + ', '.join(args) + ']'
            return "context.tr('%s'%s)" % (tmpl, a)
        new = LIT.sub(sub, line)
        if new != line:
            lines[n] = new
            changed = True
    if changed:
        s = '\n'.join(lines)
        # drop const from expressions that now contain context.tr
        for _ in range(6):
            s = re.sub(r'\bconst\s+((?:[A-Z]\w*)(?:<[^>]*>)?(?:\.\w+)?\((?:[^()]|\([^()]*\))*context\.tr\()', r'\1', s)
            s = re.sub(r'\bconst\s+(\[(?:[^\[\]]|\[[^\[\]]*\])*context\.tr\()', r'\1', s)
        if "import '../i18n/i18n.dart';" not in s and "import 'i18n/i18n.dart';" not in s:
            rel = "'i18n/i18n.dart'" if f.replace('\\', '/').count('/') == 1 else "'../i18n/i18n.dart'"
            s = re.sub(r"(import 'package:flutter/material.dart';)", r"\1\n\nimport %s;" % rel, s, count=1)
        Path(f).write_text(s, encoding='utf-8')
        print('updated', f)

uniq = sorted(set(keys))
Path('tool/strings_zh.txt').write_text('\n'.join(uniq), encoding='utf-8')
print(len(keys), 'literals,', len(uniq), 'unique')
