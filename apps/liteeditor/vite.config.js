import { defineConfig } from 'vite'

// 冒烟测试时可用 SMOKE_STUB=sheet,image 把尚未完成的编辑器替换为空实现，避免阻塞其他编辑器的测试
const stubs = (process.env.SMOKE_STUB ?? '').split(',').filter(Boolean)
const CLASSES = { sheet: 'SheetEditor', image: 'ImageEditor', doc: 'DocEditor', geo: 'GeoEditor', slides: 'SlidesEditor', video: 'VideoEditor', midi: 'MidiEditor' }
const stubPlugin = {
    name: 'smoke-stub',
    enforce: 'pre',
    resolveId(id, importer) {
        const m = /editors\/(\w+)\/(index|dialogs)\.js$/.exec(id)
        if (m && stubs.includes(m[1]) && importer?.replace(/\\/g, '/').endsWith('src/main.js')) return '\0stub:' + m[1]
    },
    load(id) {
        if (!id.startsWith('\0stub:')) return
        const k = id.slice(6)
        return `import { Editor } from '/src/editors/base.js'\nexport class ${CLASSES[k]} extends Editor {}\nexport async function askCanvasSize() { return null }\n`
    },
}

export default defineConfig({
    base: './',
    root: '.',
    publicDir: 'public',
    build: {
        outDir: 'dist',
        emptyOutDir: true,
        target: 'esnext',
        chunkSizeWarningLimit: 4096,
        assetsInlineLimit: 0,
        rollupOptions: { input: { main: 'index.html', shot: 'shot.html', recbar: 'recbar.html' } },
    },
    plugins: [stubPlugin],
    worker: { format: 'es' },
    server: { port: 5199, strictPort: true },
})
