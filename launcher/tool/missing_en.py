"""Prints trGlobal('…') keys from the given Dart files that have no English entry in lib/i18n/strings_en*.dart."""
import pathlib
import re
import sys

CALL = re.compile(r"trGlobal\('((?:[^'\\]|\\.)*)'")
ENTRY = re.compile(r"^\s*'((?:[^'\\]|\\.)*)':", re.M)

keys = []
for f in sys.argv[1:]:
    for m in CALL.finditer(pathlib.Path(f).read_text(encoding='utf-8')):
        if m.group(1) not in keys:
            keys.append(m.group(1))
existing = set()
for f in pathlib.Path(__file__).resolve().parent.parent.joinpath('lib', 'i18n').glob('strings_en*.dart'):
    existing.update(m.group(1) for m in ENTRY.finditer(f.read_text(encoding='utf-8')))
for k in keys:
    if k not in existing:
        print(k)
