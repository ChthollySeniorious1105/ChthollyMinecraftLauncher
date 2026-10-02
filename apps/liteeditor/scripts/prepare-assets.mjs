// 将运行时需要的静态资源复制到 public/vendor
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

// 导出 PDF / 打印时，隐藏窗口需要 KaTeX 样式与字体
copy(nm('katex/dist/katex.min.css'), out('katex/katex.min.css'))
copy(nm('katex/dist/fonts'), out('katex/fonts'))
console.log('[prepare-assets] done')
