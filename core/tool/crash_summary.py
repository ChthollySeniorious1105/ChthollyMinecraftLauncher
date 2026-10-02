"""Summarises tool/crash_probe.dart output: one line per (version, finding) with a count."""
import re
import sys

cur = None
seen = {}
for line in sys.stdin.read().splitlines():
    if line.startswith('OK ') or line.startswith('  ?'):
        cur = re.split(r'[\\/]crash-reports', re.sub(r'.*versions[\\/]', '', line[4:]))[0]
        if line.startswith('  ?'):
            seen[(cur, '(no finding)')] = seen.get((cur, '(no finding)'), 0) + 1
        continue
    if line.startswith('analyzed'):
        print(line)
        continue
    if line.strip().startswith('['):
        key = (cur, line.strip()[:170])
        seen[key] = seen.get(key, 0) + 1
for (v, f), n in seen.items():
    print(f'{n:>2}x {v} :: {f}')
