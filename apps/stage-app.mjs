// Stages a runnable app folder for CML's shared Electron runtime: apps/<id>/out/app
//   node apps/stage-app.mjs <desktoppet|liteeditor|litereader>
// The folder is launched as `apps/runtime/electron.exe apps/<id>/app` and contains only what the main
// process and renderers need at runtime: a trimmed package.json, the app sources / vite build output, and
// the production node_modules that are loaded at runtime (everything else is bundled by vite).
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const APPS = path.dirname(fileURLToPath(import.meta.url))

const SPEC = {
    desktoppet: {
        // plain Electron, no bundler: ship the sources and assets as-is
        files: ['src', 'assets'],
        // the global keyboard / mouse hook (bongo board) is a native module loaded with node-gyp-build
        deps: ['uiohook-napi'],
    },
    liteeditor: {
        // electron/ is the main process + preload; dist/ is the vite build (incl. public/vendor + soundfonts)
        files: ['electron', 'dist', 'build/icon.png'],
        // main process only imports electron + node builtins; all renderer deps are bundled into dist/
        deps: [],
    },
    litereader: {
        files: ['electron', 'dist', 'build/icon.png'],
        // loaded by the main process at runtime (doc:extract / audio:meta)
        deps: ['word-extractor', 'music-metadata'],
    },
}

// per-package trimming: keep only what is needed on win32-x64
const PRUNE = {
    'uiohook-napi': rel => rel.startsWith('prebuilds/') ? !rel.startsWith('prebuilds/win32-x64') : /^(src|libuiohook)(\/|$)|^binding\.gyp$/.test(rel),
}
// files never needed at runtime (directories are kept as-is: some packages ship code under lib/test-like names)
const JUNK = /\.(map|d\.ts|d\.mts|d\.cts|md|markdown)$/i

const id = process.argv[2]
const spec = SPEC[id]
if (!spec) { console.error('usage: node stage-app.mjs <' + Object.keys(SPEC).join('|') + '>'); process.exit(2) }
const src = path.join(APPS, id)
const out = path.join(src, 'out', 'app')
fs.rmSync(path.join(src, 'out'), { recursive: true, force: true })
fs.mkdirSync(out, { recursive: true })

const copyTree = (from, to, filter = () => true, base = from) => {
    const st = fs.statSync(from)
    const rel = path.relative(base, from).replace(/\\/g, '/')
    if (rel && !filter(rel, st.isDirectory())) return
    if (st.isDirectory()) {
        fs.mkdirSync(to, { recursive: true })
        for (const n of fs.readdirSync(from)) copyTree(path.join(from, n), path.join(to, n), filter, base)
    } else {
        fs.mkdirSync(path.dirname(to), { recursive: true })
        fs.copyFileSync(from, to)
    }
}

// 1. app files
for (const f of spec.files) {
    const from = path.join(src, f)
    if (!fs.existsSync(from)) { console.error(`[stage ${id}] missing ${f} (did the build run?)`); process.exit(1) }
    copyTree(from, path.join(out, f))
}

// 2. production runtime dependencies (transitive closure, resolved the same way Node does)
const staged = new Map()   // package dir -> version
function resolvePkg(name, fromDir) {
    for (let d = fromDir; ; d = path.dirname(d)) {
        const p = path.join(d, 'node_modules', name)
        if (fs.existsSync(path.join(p, 'package.json'))) return p
        if (d === src || path.dirname(d) === d) return null
    }
}
function addDep(name, fromDir, optional = false) {
    const dir = resolvePkg(name, fromDir)
    if (!dir) { if (!optional) { console.error(`[stage ${id}] cannot resolve ${name}`); process.exit(1) } return }
    if (staged.has(dir)) return
    const pj = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'))
    staged.set(dir, pj.version)
    const rel = path.relative(src, dir)
    const prune = PRUNE[pj.name]
    copyTree(dir, path.join(out, rel), (r, isDir) => {
        if (r === 'node_modules' || r.startsWith('node_modules/')) return false   // nested deps are staged on their own
        if (r === 'package.json' || /^LICEN[CS]E/i.test(r)) return true
        if (prune && prune(r)) return false
        return isDir || !JUNK.test(r)
    })
    for (const d of Object.keys(pj.dependencies ?? {})) addDep(d, dir)
    for (const d of Object.keys(pj.optionalDependencies ?? {})) addDep(d, dir, true)
}
for (const d of spec.deps) addDep(d, src)

// 3. trimmed package.json: "main" + identity, only the dependencies that are actually shipped
const pkg = JSON.parse(fs.readFileSync(path.join(src, 'package.json'), 'utf8'))
const outPkg = {
    name: pkg.name, productName: pkg.productName, version: pkg.version, description: pkg.description,
    main: pkg.main, ...(pkg.type ? { type: pkg.type } : {}), author: pkg.author, ...(pkg.license ? { license: pkg.license } : {}),
    dependencies: Object.fromEntries(spec.deps.map(d => [d, staged.get(path.join(src, 'node_modules', d))])),
    cml: { runtime: 'electron', electron: JSON.parse(fs.readFileSync(path.join(src, 'node_modules', 'electron', 'package.json'), 'utf8')).version },
}
fs.writeFileSync(path.join(out, 'package.json'), JSON.stringify(outPkg, null, 2) + '\n')

const du = p => fs.statSync(p).isDirectory() ? fs.readdirSync(p).reduce((a, n) => a + du(path.join(p, n)), 0) : fs.statSync(p).size
console.log(`[stage ${id}] ${path.relative(APPS, out)}  ${(du(out) / 1048576).toFixed(1)} MB  node_modules: ${[...staged].map(([d, v]) => `${path.relative(path.join(src, 'node_modules'), d).replace(/\\/g, '/')}@${v}`).join(', ') || '(none)'}`)
