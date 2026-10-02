// 运行冒烟测试：node scripts/run-smoke.mjs [测试名...]
// 每个测试使用独立的构建目录与用户数据目录，可以并行运行
import { spawnSync, spawn } from 'node:child_process'
import path from 'node:path'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import electron from 'electron'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const args = process.argv.slice(2)
const noBuild = args.includes('--no-build')
const names = args.filter(a => !a.startsWith('--'))
const tests = names.length ? names : fs.readdirSync(path.join(root, 'test')).filter(f => f.endsWith('.mjs')).map(f => f.replace(/\.mjs$/, ''))
const tag = process.env.SMOKE_TAG ?? names.join('-') ?? 'all'
const dist = path.join(root, '.tmp', 'dist-' + (tag || 'all'))

if (!noBuild) {
    const r = spawnSync(process.execPath, [path.join(root, 'node_modules/vite/bin/vite.js'), 'build', '--outDir', dist, '--emptyOutDir', '--logLevel', 'warn'], { cwd: root, stdio: 'inherit' })
    if (r.status) process.exit(r.status)
}

let failed = 0
for (const t of tests) {
    // 每次都从干净的用户数据开始（窗口尺寸、设置一致）
    fs.rmSync(path.join(root, '.tmp', 'userdata-' + t), { recursive: true, force: true })
    const code = await new Promise(resolve => {
        const child = spawn(electron, [path.join(root, 'scripts/smoke.mjs'), '--run', path.join(root, 'test', t + '.mjs')], {
            cwd: root, stdio: 'inherit',
            env: { ...process.env, LITE_DIST: dist, LITE_USERDATA: path.join(root, '.tmp', 'userdata-' + t) },
        })
        child.on('close', resolve)
    })
    if (code) failed++
}
process.exit(failed ? 1 : 0)
