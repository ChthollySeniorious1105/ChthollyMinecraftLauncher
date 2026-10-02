const { contextBridge, ipcRenderer } = require('electron');

const on = (channel, cb) => {
  const fn = (_e, payload) => cb(payload);
  ipcRenderer.on(channel, fn);
  return () => ipcRenderer.removeListener(channel, fn);
};

contextBridge.exposeInMainWorld('api', {
  store: {
    get: key => ipcRenderer.sendSync('store:get', key),
    set: (key, value) => ipcRenderer.send('store:set', key, value)
  },
  settings: {
    get: () => ipcRenderer.sendSync('settings:get'),
    update: patch => ipcRenderer.send('settings:update', patch),
    onChange: cb => on('settings', cb)
  },
  pets: () => ipcRenderer.sendSync('pets:list'),
  petImage: file => ipcRenderer.sendSync('pets:image', file),
  pet: {
    drag: (dx, dy) => ipcRenderer.send('pet:drag', dx, dy),
    dragEnd: () => ipcRenderer.send('pet:dragEnd'),
    ignoreMouse: ignore => ipcRenderer.send('pet:ignoreMouse', ignore),
    onHover: cb => on('pet:hover', cb),
    contextMenu: () => ipcRenderer.send('pet:contextMenu'),
    say: (text, mood, ms) => ipcRenderer.send('pet:say', { text, mood, ms }),
    onSay: cb => on('pet:say', cb),
    onWalk: cb => on('pet:walk', cb),
    onFling: cb => on('pet:fling', cb)
  },
  hub: {
    open: page => ipcRenderer.send('hub:open', page),
    onOpen: cb => on('hub:open', cb),
    minimize: () => ipcRenderer.send('hub:minimize'),
    toggleMax: () => ipcRenderer.send('hub:toggleMax'),
    close: () => ipcRenderer.send('hub:close')
  },
  pomo: {
    get: () => ipcRenderer.sendSync('pomo:get'),
    start: () => ipcRenderer.send('pomo:start'),
    pause: () => ipcRenderer.send('pomo:pause'),
    reset: () => ipcRenderer.send('pomo:reset'),
    skip: () => ipcRenderer.send('pomo:skip'),
    mode: m => ipcRenderer.send('pomo:mode', m),
    cfg: c => ipcRenderer.send('pomo:cfg', c),
    onChange: cb => on('pomo', cb)
  },
  notify: (title, body) => ipcRenderer.send('notify', title, body),
  care: {
    get: () => ipcRenderer.sendSync('care:get'),
    action: (action, item) => ipcRenderer.sendSync('care:action', action, item),
    reward: (coins, reason) => ipcRenderer.send('care:reward', coins, reason),
    onChange: cb => on('care', cb)
  },
  alarms: {
    get: () => ipcRenderer.sendSync('alarms:get'),
    setAlarms: list => ipcRenderer.send('alarms:set', list),
    setCountdowns: list => ipcRenderer.send('countdowns:set', list),
    onChange: cb => on('alarms', cb),
    onRing: cb => on('alarm:ring', cb)
  },
  sys: () => ipcRenderer.sendSync('sys:get'),
  bongo: {
    toggle: () => ipcRenderer.send('bongo:toggle'),
    get: () => ipcRenderer.sendSync('bongo:get'),
    update: patch => ipcRenderer.send('bongo:update', patch),
    drag: (dx, dy) => ipcRenderer.send('bongo:drag', dx, dy),
    ignore: v => ipcRenderer.send('bongo:ignore', v),
    menu: () => ipcRenderer.send('bongo:menu'),
    onKey: cb => on('bongo:key', cb),
    onMouse: cb => on('bongo:mouse', cb),
    onMove: cb => on('bongo:move', cb),
    onWheel: cb => on('bongo:wheel', cb),
    onCfg: cb => on('bongo:cfg', cb)
  },
  launch: {
    pick: kind => ipcRenderer.invoke('launch:pick', kind),
    icon: target => ipcRenderer.invoke('launch:icon', target),
    open: item => ipcRenderer.invoke('launch:open', item)
  },
  ach: {
    get: () => ipcRenderer.sendSync('ach:get'),
    bump: key => ipcRenderer.send('stats:bump', key),
    set: (key, value) => ipcRenderer.send('stats:set', key, value),
    onUnlock: cb => on('achievement', cb)
  },
  play: {
    get: () => ipcRenderer.sendSync('play:get'),
    trip: id => ipcRenderer.sendSync('play:trip', id),
    claim: () => ipcRenderer.sendSync('play:claim'),
    recall: () => ipcRenderer.sendSync('play:recall'),
    fish: f => ipcRenderer.sendSync('play:fish', f),
    garden: (op, a) => ipcRenderer.sendSync('play:garden', op, a),
    gacha: () => ipcRenderer.sendSync('play:gacha'),
    onChange: cb => on('play', cb)
  },
  clips: {
    get: () => ipcRenderer.sendSync('clips:get'),
    set: list => ipcRenderer.send('clips:set', list),
    copy: text => ipcRenderer.send('clips:copy', text),
    onChange: cb => on('clips', cb)
  },
  backup: {
    exportData: () => ipcRenderer.invoke('data:export'),
    importData: () => ipcRenderer.invoke('data:import')
  },
  quit: () => ipcRenderer.send('app:quit'),
  debug: msg => ipcRenderer.send('debug', msg)
});

// CML theme bridge: the main process reads / watches theme.json (src/theme-bridge.js); see src/shared/cml-theme.js
contextBridge.exposeInMainWorld('cmlTheme', {
  get: () => ipcRenderer.sendSync('cml-theme:get'),
  onChange: cb => on('cml-theme:changed', cb)
});
