const { contextBridge, ipcRenderer, webUtils } = require('electron')

contextBridge.exposeInMainWorld('lite', {
    platform: process.platform,
    openDialog: opts => ipcRenderer.invoke('dialog:open', opts),
    saveFile: opts => ipcRenderer.invoke('dialog:save', opts),
    readFile: p => ipcRenderer.invoke('fs:read', p),
    writeFile: (p, data) => ipcRenderer.invoke('fs:write', p, data),
    exists: p => ipcRenderer.invoke('fs:exists', p),
    savePath: opts => ipcRenderer.invoke('dialog:save-path', opts),
    pickFolder: opts => ipcRenderer.invoke('dialog:folder', opts),
    printHtml: opts => ipcRenderer.invoke('print:html', opts),
    printAsset: (data, ext) => ipcRenderer.invoke('print:asset', data, ext),
    renderPng: opts => ipcRenderer.invoke('render:png', opts),
    stat: p => ipcRenderer.invoke('fs:stat', p),
    findFirst: (base, exts) => ipcRenderer.invoke('fs:find-first', base, exts),
    listDir: dir => ipcRenderer.invoke('fs:list-dir', dir),
    extractDoc: src => ipcRenderer.invoke('doc:extract', src),
    extractChm: p => ipcRenderer.invoke('chm:extract', p),
    audioMeta: src => ipcRenderer.invoke('audio:meta', src),
    showInFolder: p => ipcRenderer.invoke('shell:show', p),
    openExternal: url => ipcRenderer.invoke('shell:open-external', url),
    takeFiles: () => ipcRenderer.invoke('app:take-files'),
    appInfo: () => ipcRenderer.invoke('app:info'),
    pathForFile: file => {
        try { return webUtils.getPathForFile(file) } catch { return '' }
    },
    win: {
        minimize: () => ipcRenderer.send('win:minimize'),
        toggleMaximize: () => ipcRenderer.send('win:toggle-maximize'),
        close: () => ipcRenderer.send('win:close'),
        setFullscreen: v => ipcRenderer.send('win:set-fullscreen', v),
        state: () => ipcRenderer.invoke('win:state'),
        setBackground: bg => ipcRenderer.send('win:set-bg', bg),
    },
    on: (channel, cb) => {
        const allowed = ['win:state', 'app:open-files']
        if (!allowed.includes(channel)) return () => {}
        const listener = (_e, ...args) => cb(...args)
        ipcRenderer.on(channel, listener)
        return () => ipcRenderer.removeListener(channel, listener)
    },
})

// CML 主题桥：主进程读取并监视 theme.json，这里同步取当前主题并订阅变化
contextBridge.exposeInMainWorld('cmlTheme', {
    get: () => ipcRenderer.sendSync('cml-theme:get'),
    onChange: cb => {
        const listener = (_e, t) => cb(t)
        ipcRenderer.on('cml-theme:changed', listener)
        return () => ipcRenderer.removeListener('cml-theme:changed', listener)
    },
})
