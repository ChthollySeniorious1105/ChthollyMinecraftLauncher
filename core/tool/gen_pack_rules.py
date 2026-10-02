"""Derives CML's Java resource-pack migration rules by diffing consecutive vanilla client jars.

For each adjacent pair (A -> B) it finds:
  * renames: a texture/model/blockstate/sound that disappeared from A and appears in B with the same
    content (pixels for PNGs, normalised JSON for models) — or for PNGs with a near-identical perceptual hash.
  * slices: a texture that disappeared from A whose pixels contain a new texture of B (e.g. gui/icons ->
    gui/sprites/hud/heart/full). Located by exact sub-image search.
  * merges: the reverse of slices (several A textures pasted into one new B texture).
  * removed / added paths.

Usage: python tool/gen_pack_rules.py <dir with <version>.jar files>
Writes lib/src/resourcepack/data/pack_rules_data.dart
"""
import base64, gzip, hashlib, io, json, re, sys, zipfile
from pathlib import Path

import numpy as np
from PIL import Image

ORDER = ['1.8.9', '1.12.2', '1.13.2', '1.14.4', '1.15.2', '1.16.5', '1.17.1', '1.18.2', '1.19.2', '1.19.3', '1.19.4', '1.20.1',
         '1.20.2', '1.20.4', '1.20.6', '1.21.1', '1.21.3', '1.21.4', '1.21.5', '1.21.8', '1.21.10', '1.21.11', '26.1.2', '26.2']
jar_dir = Path(sys.argv[1])

PREFIX = 'assets/minecraft/'


def load(v):
    out = {}
    with zipfile.ZipFile(jar_dir / f'{v}.jar') as z:
        meta = None
        for n in z.namelist():
            if not n.startswith(PREFIX) or n.endswith('/'):
                continue
            rel = n[len(PREFIX):]
            if rel.startswith(('textures/', 'models/', 'blockstates/', 'items/', 'atlases/', 'equipment/', 'particles/', 'font/')):
                out[rel] = z.read(n)
        try:
            vj = json.loads(z.read('version.json'))
            pv = vj.get('pack_version')
            meta = pv if isinstance(pv, int) else (pv or {}).get('resource_major', pv.get('resource') if isinstance(pv, dict) else None)
        except KeyError:
            meta = None
    return out, meta


def img(b):
    try:
        return np.asarray(Image.open(io.BytesIO(b)).convert('RGBA'))
    except Exception:
        return None


def pix_key(a):
    return hashlib.sha1(a.tobytes() + str(a.shape).encode()).hexdigest()


def json_key(b):
    try:
        return hashlib.sha1(json.dumps(json.loads(b), sort_keys=True).encode()).hexdigest()
    except Exception:
        return hashlib.sha1(b).hexdigest()


def find_sub(big, small):
    """Exact sub-image search; returns (x, y) or None. Fully transparent smalls are skipped."""
    bh, bw = big.shape[:2]
    sh, sw = small.shape[:2]
    if sh > bh or sw > bw or sh * sw < 16 or small[..., 3].max() == 0:
        return None
    # anchor on the first opaque pixel of small
    ys, xs = np.nonzero(small[..., 3])
    ay, ax = ys[0], xs[0]
    anchor = small[ay, ax]
    cand = np.argwhere(np.all(big == anchor, axis=-1))
    for cy, cx in cand[:4000]:
        y, x = cy - ay, cx - ax
        if y < 0 or x < 0 or y + sh > bh or x + sw > bw:
            continue
        win = big[y:y + sh, x:x + sw]
        # compare only where small is opaque, transparent area must be transparent too
        if np.array_equal(win, small):
            return int(x), int(y)
    return None


def diff(a, b, va, vb):
    rules = {'from': va, 'to': vb, 'rename': {}, 'slice': [], 'merge': [], 'removed': [], 'added': []}
    gone = [k for k in a if k not in b]
    new = [k for k in b if k not in a]
    # ---- textures
    gone_png = [k for k in gone if k.endswith('.png')]
    new_png = [k for k in new if k.endswith('.png')]
    gone_img = {k: img(a[k]) for k in gone_png}
    new_img = {k: img(b[k]) for k in new_png}
    by_key = {}
    for k, im in gone_img.items():
        if im is not None:
            by_key.setdefault(pix_key(im), []).append(k)
    matched_new = set()
    matched_gone = set()
    for k, im in new_img.items():
        if im is None:
            continue
        hit = by_key.get(pix_key(im))
        if hit:
            src = min(hit, key=lambda s: _name_dist(s, k))
            rules['rename'][src] = k
            matched_new.add(k)
            matched_gone.add(src)
    # same-name-different-folder renames even if pixels changed (art update + move)
    gone_by_name = {}
    for k in gone_png:
        if k not in matched_gone:
            gone_by_name.setdefault(Path(k).name, []).append(k)
    for k in new_png:
        if k in matched_new:
            continue
        c = gone_by_name.get(Path(k).name)
        if c and len(c) == 1 and gone_img.get(c[0]) is not None and new_img.get(k) is not None and gone_img[c[0]].shape == new_img[k].shape:
            rules['rename'][c[0]] = k
            matched_new.add(k)
            matched_gone.add(c[0])
    # slices: remaining new textures found inside a remaining gone texture (or a still-existing big atlas)
    big_sources = [k for k in gone_png if k not in matched_gone and gone_img.get(k) is not None and gone_img[k].shape[0] * gone_img[k].shape[1] >= 64 * 64]
    slices = {}
    for k in new_png:
        if k in matched_new or new_img.get(k) is None:
            continue
        sm = new_img[k]
        for src in big_sources:
            pos = find_sub(gone_img[src], sm)
            if pos:
                slices.setdefault(src, []).append([k, pos[0], pos[1], int(sm.shape[1]), int(sm.shape[0]), int(gone_img[src].shape[1]), int(gone_img[src].shape[0])])
                matched_new.add(k)
                break
    for src, parts in slices.items():
        rules['slice'].append({'src': src, 'parts': parts})
        matched_gone.add(src)
    # art changed but path moved within the same folder with a related name (e.g. 1.13 fish_cod_raw -> cod)
    rest_gone = [k for k in gone_png if k not in matched_gone and gone_img.get(k) is not None]
    rest_new = [k for k in new_png if k not in matched_new and new_img.get(k) is not None]
    for k in rest_gone:
        stem_tokens = set(re.split(r'[_/]', Path(k).stem)) - {'raw', 'colored', 'normal'}
        best, best_score = None, 0.0
        for n in rest_new:
            if n in matched_new or new_img[n].shape != gone_img[k].shape:
                continue
            if Path(n).parent.name.rstrip('s') != Path(k).parent.name.rstrip('s'):
                continue
            nt = set(re.split(r'[_/]', Path(n).stem))
            score = len(stem_tokens & nt) / max(1, len(stem_tokens | nt))
            if score > best_score:
                best, best_score = n, score
        if best and best_score >= 0.5:
            rules['rename'][k] = best
            matched_gone.add(k)
            matched_new.add(best)
    # .mcmeta sidecars follow their PNG
    for src, dst in list(rules['rename'].items()):
        if src.endswith('.png') and src + '.mcmeta' in a and dst + '.mcmeta' in b:
            rules['rename'][src + '.mcmeta'] = dst + '.mcmeta'
            matched_gone.add(src + '.mcmeta')
            matched_new.add(dst + '.mcmeta')
    # merges: remaining new big textures composed from remaining gone smalls
    small_gone = [k for k in gone_png if k not in matched_gone and gone_img.get(k) is not None]
    for k in new_png:
        if k in matched_new or new_img.get(k) is None:
            continue
        big = new_img[k]
        if big.shape[0] * big.shape[1] < 64 * 64:
            continue
        parts = []
        for s in small_gone:
            pos = find_sub(big, gone_img[s])
            if pos:
                parts.append([s, pos[0], pos[1], int(gone_img[s].shape[1]), int(gone_img[s].shape[0])])
        if len(parts) >= 2:
            rules['merge'].append({'dst': k, 'w': int(big.shape[1]), 'h': int(big.shape[0]), 'parts': parts})
            matched_new.add(k)
            for p in parts:
                matched_gone.add(p[0])
    # ---- json files (models / blockstates / items / atlases)
    gone_json = [k for k in gone if k.endswith('.json')]
    new_json = [k for k in new if k.endswith('.json')]
    by_j = {}
    for k in gone_json:
        by_j.setdefault(json_key(a[k]), []).append(k)
    for k in new_json:
        hit = by_j.get(json_key(b[k]))
        if hit:
            src = min(hit, key=lambda s: _name_dist(s, k))
            rules['rename'][src] = k
            matched_new.add(k)
            matched_gone.add(src)
    # model/blockstate name pairs following a texture rename (e.g. models/block/grass -> models/block/grass_block)
    tex_renames = {Path(s).stem: Path(d).stem for s, d in rules['rename'].items() if s.startswith('textures/')}
    for k in gone_json:
        if k in matched_gone:
            continue
        stem = Path(k).stem
        if stem in tex_renames:
            cand = str(Path(k).with_name(tex_renames[stem] + '.json')).replace('\\', '/')
            if cand in b and cand not in a:
                rules['rename'][k] = cand
                matched_gone.add(k)
                matched_new.add(cand)
    # vanilla metadata of new GUI sprites (9-slice scaling); packs rarely ship it themselves
    rules['meta'] = {}
    for k in sorted(matched_new):
        if k.startswith('textures/gui/sprites/') and k.endswith('.png') and k + '.mcmeta' in b:
            rules['meta'][k + '.mcmeta'] = b[k + '.mcmeta'].decode('utf-8', 'replace')
    rules['removed'] = sorted(k for k in gone if k not in matched_gone)
    rules['added'] = sorted(k for k in new if k not in matched_new)
    return rules


def _name_dist(a, b):
    na, nb = Path(a).stem, Path(b).stem
    s = len(set(na) ^ set(nb))
    if Path(a).parent.name == Path(b).parent.name:
        s -= 3
    return s


steps = []
formats = {}
prev, prev_meta = load(ORDER[0])
formats[ORDER[0]] = prev_meta
for v in ORDER[1:]:
    cur, meta = load(v)
    formats[v] = meta
    r = diff(prev, cur, steps and steps[-1]['to'] or ORDER[0], v)
    print(f"{r['from']:>8} -> {v:<8} rename {len(r['rename']):4}  slice {len(r['slice']):3} ({sum(len(s['parts']) for s in r['slice'])} parts)  merge {len(r['merge']):3}  removed {len(r['removed']):4}  added {len(r['added']):4}")
    steps.append(r)
    prev = cur

# texture rename used for model JSON reference rewriting is derived at runtime from 'rename'
data = {'versions': ORDER, 'formats': formats, 'steps': steps}
blob = base64.b64encode(gzip.compress(json.dumps(data, separators=(',', ':')).encode(), 9)).decode()
out = ['// GENERATED by tool/gen_pack_rules.py by diffing vanilla client jars ' + ORDER[0] + ' … ' + ORDER[-1] + '.',
       '// gzip JSON: {versions, formats, steps:[{from,to,rename,slice,merge,removed,added}]}',
       'const packRulesGz =']
out += ["    '%s'" % blob[i:i + 120] for i in range(0, len(blob), 120)]
out[-1] += ';'
Path('lib/src/resourcepack/data').mkdir(parents=True, exist_ok=True)
Path('lib/src/resourcepack/data/pack_rules_data.dart').write_text('\n'.join(out) + '\n', encoding='utf-8')
print('size', len(blob), 'formats', formats)
