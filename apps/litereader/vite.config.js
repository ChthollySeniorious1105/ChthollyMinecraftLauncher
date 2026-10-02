import { defineConfig } from 'vite'

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
    },
    worker: { format: 'es' },
    optimizeDeps: { exclude: ['foliate-js', 'libarchive.js'] },
    server: { port: 5188, strictPort: true },
})
