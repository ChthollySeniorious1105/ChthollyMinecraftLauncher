// 开发模式：启动 Vite 开发服务器并以其地址运行 Electron
import { createServer } from 'vite'
import { spawn } from 'node:child_process'
import electron from 'electron'

const server = await createServer()
await server.listen()
const url = server.resolvedUrls.local[0]
const child = spawn(electron, ['.'], {
    stdio: 'inherit',
    env: { ...process.env, VITE_DEV_SERVER_URL: url },
})
child.on('close', () => { server.close(); process.exit() })
