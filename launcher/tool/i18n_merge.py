"""Merges adjacent `trGlobal('a')\n  trGlobal('b')` (from Dart implicit string concatenation) and
rebuilds tool/strings_zh.txt from the final sources."""
import glob
import re

BS = chr(92)
LIT = "'((?:[^'" + BS + BS + "]|" + BS + BS + ".)*)'"
PAIR = re.compile(r"trGlobal\(" + LIT + r"\)(\s*\n\s*)trGlobal\(" + LIT + r"\)")
ONE = re.compile(r"trGlobal\(" + LIT)

for f in glob.glob('lib/**/*.dart', recursive=True):
    s = open(f, encoding='utf-8').read()
    o = s
    while True:
        n = PAIR.sub(lambda m: "trGlobal('" + m.group(1) + m.group(3) + "')", s)
        if n == s:
            break
        s = n
    if s != o:
        open(f, 'w', encoding='utf-8').write(s)
        print('merged', f)

keys = set()
for f in glob.glob('lib/**/*.dart', recursive=True):
    if 'i18n' in f:
        continue
    for m in ONE.finditer(open(f, encoding='utf-8').read()):
        keys.add(m.group(1).replace(BS + "'", "'"))
open('tool/strings_zh.txt', 'w', encoding='utf-8').write('\n'.join(sorted(keys)))
print(len(keys), 'keys')
