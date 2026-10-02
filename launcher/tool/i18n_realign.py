"""Re-aligns tool/gen_strings_en.py after the key list changed.

Reads the previous key→English pairs from lib/i18n/strings_en.dart, adds [NEW] translations,
drops keys that no longer exist, and rewrites the EN block in key order."""
import re
import sys
from pathlib import Path

NEW = {
    '个文件': 'files',
    '（测试版）': ' (beta)',
}

BS = chr(92)
gen = Path('tool/gen_strings_en.py').read_text(encoding='utf-8')
dart = Path('lib/i18n/strings_en.dart').read_text(encoding='utf-8')


def undart(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == BS and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({'n': BS + 'n', "'": "'", '$': '$', BS: BS}.get(nxt, BS + nxt))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return ''.join(out)


pat = re.compile(r"^  '((?:[^'" + BS + BS + "]|" + BS + BS + ".)*)': '((?:[^'" + BS + BS + "]|" + BS + BS + ".)*)',$", re.M)
old = {undart(k): undart(v) for k, v in pat.findall(dart)}
old.update(NEW)
keys = Path('tool/strings_zh.txt').read_text(encoding='utf-8').split('\n')
missing = [k for k in keys if k not in old]
if missing:
    print('missing translations:')
    for k in missing:
        print('  ', k)
    sys.exit(1)
block = '\n'.join(old[k] for k in keys)
start = gen.index('EN = r"""') + len('EN = r"""')
end = gen.index('"""\n\n\ndef dart')
gen = gen[:start] + '\n' + block + '\n' + gen[end:]
Path('tool/gen_strings_en.py').write_text(gen, encoding='utf-8')
print('realigned', len(keys))
