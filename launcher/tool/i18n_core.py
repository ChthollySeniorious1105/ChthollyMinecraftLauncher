"""Extracts every Chinese string literal from core/lib as a translation template.

Interpolations (`$x`, `${expr}`) become `{0}`, `{1}` … ; at runtime the launcher matches a message
against these templates (regex with captures) and substitutes the captures into the English text.
Writes tool/core_strings_zh.txt.
"""
import glob
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from i18n_wrap import scan, CJK  # noqa: E402  (reuses the Dart string tokenizer)

out = set()
for f in glob.glob('../core/lib/**/*.dart', recursive=True):
    if '/data/' in f.replace('\\', '/'):
        continue
    src = Path(f).read_text(encoding='utf-8')
    for lit in scan(src):
        text = ''.join(t for k, t in lit.parts if k == 'text')
        if not CJK.search(text):
            continue
        tmpl, n = [], 0
        for k, t in lit.parts:
            if k == 'text':
                tmpl.append(t)
            else:
                tmpl.append('{%d}' % n)
                n += 1
        s = ''.join(tmpl).replace("\\'", "'").replace('\\"', '"')
        out.add(s)
Path('tool/core_strings_zh.txt').write_text('\n'.join(sorted(out)), encoding='utf-8')
print(len(out), 'core templates')
