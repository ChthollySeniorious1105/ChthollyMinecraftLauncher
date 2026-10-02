"""Wraps every Chinese UI string literal in the launcher with `trGlobal('…')`.

Uses a small Dart string tokenizer (handles nested `${…}` with quotes inside, raw and triple
strings, comments), so interpolations like `'${a ? 'x' : 'y'} 个'` are handled correctly.
Interpolations become `{0}`, `{1}` placeholders; the template keeps the original quote style.

`const` is removed from any const expression that ends up containing `trGlobal(`
(declarations `const x = …` become `final`). Literals in imports, RegExp(…) and
default-parameter positions are left alone (reported for manual handling).
Writes tool/strings_zh.txt with the unique keys for the English table.
"""
import glob
import re
from pathlib import Path

CJK = re.compile(r'[一-鿿（-？、-】]')


class Lit:
    def __init__(self, start, end, quote, parts):
        self.start, self.end, self.quote = start, end, quote
        # parts: list of ('text', str) | ('expr', str)  (expr is source text inside ${…} or $name)
        self.parts = parts


def scan(src):
    """Yields top-level (non-nested) simple string literals with their parts."""
    lits = []
    i, n = 0, len(src)

    def read_string(i):
        """src[i] is the opening quote (possibly raw/triple handled by caller). Returns (end_index_after, parts)."""
        q = src[i]
        triple = src[i:i + 3] == q * 3
        qs = q * 3 if triple else q
        j = i + len(qs)
        parts, buf = [], []
        while j < n:
            if src.startswith(qs, j):
                if buf:
                    parts.append(('text', ''.join(buf)))
                return j + len(qs), parts, triple
            c = src[j]
            if c == '\\':
                buf.append(src[j:j + 2])
                j += 2
                continue
            if c == '$' and j + 1 < n and src[j + 1] == '{':
                if buf:
                    parts.append(('text', ''.join(buf)))
                    buf = []
                k = skip_expr(j + 2)
                parts.append(('expr', src[j + 2:k]))
                j = k + 1
                continue
            if c == '$' and j + 1 < n and (src[j + 1].isalpha() or src[j + 1] == '_'):
                if buf:
                    parts.append(('text', ''.join(buf)))
                    buf = []
                m = re.match(r'[A-Za-z_]\w*', src[j + 1:])
                parts.append(('expr', m.group(0)))
                j += 1 + len(m.group(0))
                continue
            buf.append(c)
            j += 1
        return n, parts, triple

    def skip_raw(i):
        q = src[i]
        qs = q * 3 if src[i:i + 3] == q * 3 else q
        j = src.find(qs, i + len(qs))
        return n if j < 0 else j + len(qs)

    def skip_expr(j):
        """j points after '${'. Returns index of the matching '}'."""
        depth = 1
        while j < n:
            c = src[j]
            if c in '\'"':
                j, _, _ = read_string(j)
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return n

    while i < n:
        c = src[i]
        if src.startswith('//', i):
            e = src.find('\n', i)
            i = n if e < 0 else e
            continue
        if src.startswith('/*', i):
            e = src.find('*/', i + 2)
            i = n if e < 0 else e + 2
            continue
        if c == 'r' and i + 1 < n and src[i + 1] in '\'"' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            i = skip_raw(i + 1)
            continue
        if c in '\'"':
            end, parts, triple = read_string(i)
            if not triple:
                lits.append(Lit(i, end, c, parts))
            i = end
            continue
        i += 1
    return lits


def line_of(src, pos):
    s = src.rfind('\n', 0, pos) + 1
    e = src.find('\n', pos)
    return src[s:e if e >= 0 else len(src)]


def context_before(src, pos, width=40):
    return src[max(0, pos - width):pos]


keys = []
skipped = []


def wrap_file(path):
    src = Path(path).read_text(encoding='utf-8')
    out, last = [], 0
    for lit in scan(src):
        text = ''.join(t for k, t in lit.parts if k == 'text')
        if not CJK.search(text):
            continue
        line = line_of(src, lit.start)
        before = context_before(src, lit.start)
        if line.lstrip().startswith('import ') or 'RegExp(' in before[-12:] or 'trGlobal(' in before[-10:]:
            continue
        # default parameter values must stay constant: `{String ok = '确定'}`
        if re.search(r'[{,(]\s*\w[\w<>?]*\s+\w+\s*=\s*$', before) and re.search(r'^\s*[,}]', src[lit.end:lit.end + 5]):
            skipped.append((path, line.strip()))
            continue
        tmpl, args = [], []
        for k, t in lit.parts:
            if k == 'text':
                tmpl.append(t)
            else:
                args.append(t)
                tmpl.append('{%d}' % (len(args) - 1))
        tmpl = ''.join(tmpl)
        q = lit.quote
        if q == '"':
            # normalise to single quotes for the key
            tmpl = tmpl.replace("\\\"", '"').replace("'", "\\'")
        keys.append(tmpl.replace("\\'", "'"))
        call = "trGlobal('%s'%s)" % (tmpl, '' if not args else ', [' + ', '.join(args) + ']')
        out.append(src[last:lit.start])
        out.append(call)
        last = lit.end
    if not out:
        return False
    out.append(src[last:])
    s = strip_const(''.join(out))
    depth = path.replace('\\', '/').count('/') - 1
    imp = "import '%si18n/i18n.dart';" % ('../' * depth)
    if 'i18n/i18n.dart' not in s:
        last_imp = list(re.finditer(r"^import 'package:[^']+';\n", s, re.M))
        pos = last_imp[-1].end() if last_imp else 0
        s = s[:pos] + '\n' + imp + '\n' + s[pos:]
    Path(path).write_text(s, encoding='utf-8')
    return True


def span_end(s, j):
    depth, k = 0, j
    lits = {l.start: l.end for l in scan(s[j:])}
    while k < len(s):
        if (k - j) in lits:
            k = j + lits[k - j]
            continue
        c = s[k]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return k
        k += 1
    return len(s) - 1


CONST = re.compile(r'\bconst\s+')


def strip_const(s):
    while True:
        changed = False
        for m in CONST.finditer(s):
            j = m.end()
            while j < len(s) and s[j] not in '([{;,=':
                j += 1
            decl = j < len(s) and s[j] == '='
            if decl:
                j += 1
                while j < len(s) and s[j] not in '([{;':
                    j += 1
            if j >= len(s) or s[j] == ';':
                continue
            end = span_end(s, j)
            if 'trGlobal(' in s[m.end():end + 1]:
                s = s[:m.start()] + ('final ' if decl else '') + s[m.end():]
                changed = True
                break
        if not changed:
            return s


if __name__ == '__main__':
    changed = [f for f in sorted(glob.glob('lib/**/*.dart', recursive=True)) if 'i18n' not in f and wrap_file(f)]
    for f in changed:
        print('updated', f)
    uniq = sorted(set(keys))
    Path('tool/strings_zh.txt').write_text('\n'.join(uniq), encoding='utf-8')
    print(len(keys), 'literals,', len(uniq), 'unique')
    for f, l in skipped:
        print('SKIPPED default param:', f, l[:100])
