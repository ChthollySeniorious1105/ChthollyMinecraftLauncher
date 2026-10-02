const { contextBridge, ipcRenderer, webUtils } = require('electron')

contextBridge.exposeInMainWorld('lite', {
    platform: process.platform,
    openDialog: opts => ipcRenderer.invoke('dialog:open', opts),
    saveDialog: opts => ipcRenderer.invoke('dialog:save', opts),
    message: opts => ipcRenderer.invoke('dialog:message', opts),
    readFile: p => ipcRenderer.invoke('fs:read', p),
    writeFile: (p, data) => ipcRenderer.invoke('fs:write', p, data),
    stat: p => ipcRenderer.invoke('fs:stat', p),
    htmlToPdf: (html, opts) => ipcRenderer.invoke('print:pdf', html, opts),
    printHtml: html => ipcRenderer.invoke('print:html', html),
    showInFolder: p => ipcRenderer.invoke('shell:show', p),
    openExternal: url => ipcRenderer.invoke('shell:open-external', url),
    takeFiles: () => ipcRenderer.invoke('app:take-files'),
    appInfo: () => ipcRenderer.invoke('app:info'),
    pathForFile: file => {
        try { return webUtils.getPathForFile(file) } catch { return '' }
    },
    fonts: {
        list: () => ipcRenderer.invoke('fonts:list'),
        system: () => ipcRenderer.invoke('fonts:system'),
        import: paths => ipcRenderer.invoke('fonts:import', paths),
        remove: file => ipcRenderer.invoke('fonts:remove', file),
    },
    capture: {
        sources: opts => ipcRenderer.invoke('capture:sources', opts),
        pick: id => ipcRenderer.invoke('capture:pick', id),
        displays: () => ipcRenderer.invoke('capture:displays'),
        screenshot: opts => ipcRenderer.invoke('capture:screenshot', opts),
        copyImage: dataURL => ipcRenderer.invoke('clipboard:image', dataURL),
        // 截图遮罩窗口
        shotInit: () => ipcRenderer.invoke('shot:init'),
        shotDone: v => ipcRenderer.send('shot:done', v),
        // 录制控制条
        showBar: opts => ipcRenderer.invoke('recbar:show', opts),
        hideBar: () => ipcRenderer.invoke('recbar:hide'),
        barState: st => ipcRenderer.send('recbar:state', st),
        barCmd: cmd => ipcRenderer.send('recbar:cmd', cmd),
    },
    win: {
        hide: () => ipcRenderer.invoke('win:hide'),
        show: () => ipcRenderer.invoke('win:show'),
        minimize: () => ipcRenderer.send('win:minimize'),
        toggleMaximize: () => ipcRenderer.send('win:toggle-maximize'),
        close: () => ipcRenderer.send('win:close'),
        closeConfirmed: () => ipcRenderer.send('win:close-confirmed'),
        setFullscreen: v => ipcRenderer.send('win:set-fullscreen', v),
        state: () => ipcRenderer.invoke('win:state'),
        setBackground: bg => ipcRenderer.send('win:set-bg', bg),
    },
    on: (channel, cb) => {
        const allowed = ['win:state', 'app:open-files', 'app:before-close', 'capture:hotkey', 'rec:state']
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
