// 将运行时需要的静态资源（worker / wasm / 字体映射等）复制到 public/vendor
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const nm = p => path.join(root, 'node_modules', p)
const out = p => path.join(root, 'public', 'vendor', p)

const copy = (from, to) => {
    if (!fs.existsSync(from)) return console.warn('[prepare-assets] 缺少', from)
    fs.mkdirSync(path.dirname(to), { recursive: true })
    fs.cpSync(from, to, { recursive: true })
}

copy(nm('libarchive.js/dist/worker-bundle.js'), out('libarchive/worker-bundle.js'))
copy(nm('libarchive.js/dist/libarchive.wasm'), out('libarchive/libarchive.wasm'))
copy(nm('pdfjs-dist/cmaps'), out('pdfjs/cmaps'))
copy(nm('pdfjs-dist/standard_fonts'), out('pdfjs/standard_fonts'))
copy(nm('pdfjs-dist/wasm'), out('pdfjs/wasm'))
copy(nm('pdfjs-dist/iccs'), out('pdfjs/iccs'))
copy(nm('spessasynth_lib/dist/spessasynth_processor.min.js'), out('spessasynth/spessasynth_processor.min.js'))
console.log('[prepare-assets] done')
