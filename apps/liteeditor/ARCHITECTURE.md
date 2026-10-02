# LiteEditor 架构说明（维护指南）

给接手修改的开发者 / AI 会话：读完本文即可定位代码、按既有模式扩展、并用冒烟测试验证。

- 技术栈：Electron 44 + Vite 8，**纯原生 JS（ES 模块，无框架、无 TypeScript）**，界面全部中文，图标只用 lucide。
- 项目根：`D:\Server\Others\LiteEditor`；GitHub 私密仓库 `ChthollySeniorious1105/LiteEditor`（分支 `master`）。
- 代码风格：4 空格缩进、无分号、单引号；注释用中文且简短；DOM 用 `h()` 构造，不写 HTML 模板字符串（导出 HTML 除外）。

---

## 1. 目录地图

```
electron/            主进程（Node）
  main.js            窗口、app:// 与 media:// 协议、文件 / 对话框 / 打印 IPC、单实例与文件关联
  preload.cjs        window.lite 桥（渲染进程唯一的系统接口）
  fonts.js           字体：解析 TTF/OTF/TTC/WOFF 名称表、扫描系统字体、用户字体目录 IPC
  capture.js         截图遮罩窗口、录屏源、录制控制条、全局快捷键
  theme-bridge.js    CML 主题桥：读取 / 监视 theme.json，推送 cml-theme:changed，同步 nativeTheme
index.html           主窗口（CSP 在这里）
shot.html recbar.html  截图遮罩页、录屏控制条页（src/shot/）
src/
  main.js            App 外壳：标签页、主页 / 设置页、新建模板 TEMPLATES、全局快捷键、拖放、命令面板
  core/              共享模块（见 §3）
  editors/base.js    Editor 基类（见 §4）
  editors/<kind>/    七个编辑器：image geo doc sheet slides video midi
  tools/capture.js   截图 / 录屏（渲染进程部分）
  shot/              截图遮罩与录制控制条页面脚本
  styles/            base.css（变量、按钮、弹窗）app.css（外壳页面）editor.css（通用编辑器）+ 每个编辑器一个 css
public/              静态资源：logo.svg、soundfonts/GeneralUserGS.sf3、vendor/（postinstall 生成，勿提交）
scripts/             run-smoke.mjs（测试入口）smoke.mjs（Electron 内测试驱动）prepare-assets.mjs（复制 KaTeX）
test/<name>.mjs      冒烟测试
samples/             手工测试用样例文件
```

`.gitignore` 排除：`node_modules/ dist/ release/ public/vendor/ .tmp/`。

---

## 2. 进程与协议

| 协议 | 用途 |
| --- | --- |
| `app://local/<路径>` | 生产模式加载 `dist/`（找不到时回退 `public/`）。`/__print/<id>` 为打印 / PDF 临时页面；`/__fonts/<文件>` 为用户导入字体 |
| `media://file/<encodeURIComponent(绝对路径)>` | 读取任意本地文件，支持 Range（音视频跳转）。渲染进程用 `mediaURL(path)`（core/files.js）生成 |

渲染进程**没有 Node**（`contextIsolation + sandbox`），所有系统能力通过 `window.lite`：

```
openDialog({ title, filters, multi }) -> 路径[]      saveDialog({ defaultPath, filters }) -> 路径|null
readFile(p) -> Uint8Array   writeFile(p, Uint8Array|string)   stat(p) -> { size, mtime, isFile, isDir }|null
htmlToPdf(html, { landscape, pageSize }) -> Uint8Array   printHtml(html)     // 隐藏窗口渲染，自动注入用户字体
showInFolder(p)  openExternal(url)  takeFiles()  appInfo()  pathForFile(File)  message(opts)
fonts.{ list, system, import(paths), remove(file) }
capture.{ sources, pick, displays, screenshot, copyImage, showBar, hideBar, ... }
win.{ minimize, toggleMaximize, close, setFullscreen, state, setBackground, hide, show }
on(channel, cb)   // 仅白名单：win:state app:open-files app:before-close capture:hotkey rec:state
```

**新增系统能力的步骤**：`electron/main.js`（或独立模块）里 `ipcMain.handle('域:动作', ...)` → `preload.cjs` 暴露到 `window.lite` → 若是主进程推送事件，把通道加进 `on()` 白名单。新资源类型如需被 `<img>/<video>/fetch` 读取，检查 `index.html` 的 CSP。

---

## 3. 共享模块 `src/core/`

| 文件 | 内容 |
| --- | --- |
| `dom.js` | `h('div.cls#id', props, ...children)`、`fill(el, ...)`、`btn(icon, title, onclick)`、`toast(msg, 'info'\|'success'\|'warn'\|'error')`、`dialog / formDialog / confirmDialog / unsavedDialog`、`select(options, value, onchange)`（options 支持 `{ group, options }` 分组）、`numberInput / colorInput / slider / segmented / toggle / menuButton`、`popover / togglePopover / menu`、`clamp debounce throttle escapeHTML uid sleep formatBytes formatDate` |
| `menu.js` | `openMenu(items, { anchor \| x,y })`、`contextMenu(e, items)`、`dropdown()`、`keyString(e)`（→ `'Ctrl+Shift+Z'`）、`collectKeys(menus)`。菜单项：`{ label, icon, key, altKey, run, disabled, checked, danger, submenu, swatch, title }`、`'-'`、`{ header }`、`{ el }`；label / disabled / checked / submenu 可以是函数 |
| `files.js` | `KINDS`（每种编辑器的名称、图标、颜色、`exts` 可打开、`native` 可无损保存）、`kindOf / extOf / baseName / dirName / stemOf / toBytes / bytesToText / bytesToDataURL / blobToDataURL / mediaURL / MIME / pickImage / loadImage / dialogFilters` |
| `store.js` | 设置 `get / set / getSettings / onSettings / resetSettings`（`DEFAULT_SETTINGS` 定义默认值）；最近文件；`getPref(ns, defaults) / setPref(ns, v)` 编辑器私有偏好（localStorage） |
| `history.js` | 快照式撤销栈（基类已接好，一般不直接用） |
| `theme.js` | CML 主题桥（渲染端）：`initTheme()` 经 `window.cmlTheme.get/onChange` 取主题，`applyTheme` 写 CSS 变量并派发 `themechange`；`currentTheme()`、`THEME_HINT` |
| `icons.js` | `icon('lucide-kebab-name', size)` |
| `fonts.js` | 用户字体（FontFace 注册）、系统字体、`fontSelect()` 字体下拉框、`fontOptions()`、`embedFontCSS()`、`pickAndImportFonts()`（见 §7） |
| `palette.js` | 命令面板 `openPalette(commands)`、`flattenMenus(menus)` |
| `mathkb.js` | 数学输入软键盘（几何画板用） |

主题跟随 CML 启动器（`%APPDATA%\CML\theme.json`，`CML_THEME_FILE` 优先，协议见 CML 仓库 `docs/THEME_BRIDGE.md`），应用内没有主题选择。
主进程 `electron/theme-bridge.js` 监视文件目录（150ms 防抖），通过 `cml-theme:changed` 推送；preload 暴露 `window.cmlTheme`（与 `window.lite` 分开）。
需要随主题重绘 canvas 的编辑器监听 `window` 的 `themechange` 事件（例如 midi）。

主题 CSS 变量：`--bg --surface --surface-2 --surface-3 --text --text-2 --text-3 --line --line-2 --hover --press --accent --accent-2 --accent-soft --accent-grad --on-accent --glass --shadow-1..3 --radius --ease`。
**纸张 / 画布内容保持真实颜色（白纸黑字），不随主题变色；外围 UI 一律用变量。**

---

## 4. Editor 基类（`src/editors/base.js`）

基类提供：菜单栏（自动生成“文件”菜单：新建 / 打开 / 保存 / 另存为 / 导出为 / 导入字体 / 关闭）、快捷键分发（菜单项的 `key` 自动注册）、撤销重做、未保存提示、保存 / 另存为 / 导出、自动保存、状态栏、`panel()` 右侧折叠面板、`toolRail()`、`tbGroup() / tb() / dd()` 工具栏构造、`listen() / onDispose()` 自动解绑。

布局：`this.menubar / this.toolbar / this.leftbar / this.stage / this.panels / this.status`。

### 子类契约

```js
export class XxxEditor extends Editor {
    static kind = 'xxx'
    constructor(file, app) { super(file, app); /* 构建 DOM */ }
    async create(options) {}      // 新建；options 来自 src/main.js 的 TEMPLATES
    async load(bytes, ext) {}     // 打开文件
    snapshot() {}                 // 完整状态快照（撤销用），尽量共享不可变部分
    restore(snap) {}              // 恢复快照并重绘
    menus() { return [{ label: '编辑', items: () => [...this.undoItems(), '-', ...] }] }   // 不含“文件”
    formats() { return [{ ext, name, write: async target => Uint8Array|string, lossy?: '提示' }] } // 第一个为默认保存格式
    exports() {}      // 可选：仅导出格式（PNG / PDF …）
    fileItems() {}    // 可选：文件菜单追加项
    onKey(e) {}       // 可选：优先于菜单快捷键，返回 true 表示已处理
    ownsTyping(e) {}  // 可选：焦点在编辑区时 Ctrl+Z/B/I 也交给编辑器（doc / sheet / slides 使用）
    menubarExtra() {} // 可选：菜单栏右侧附加内容
    onShow() / onHide() / destroy()
}
```

规则：

- 每次用户修改后 `this.commit('操作名')`；拖动 / 滑块连续修改用 `this.commit('调整', { merge: 'key' })` 合并为一步。
- 长任务期间设 `this.busy = true`（不会触发自动保存）。
- 保存到 `KINDS[kind].native` 中的格式才算“已保存”，其他都属于导出。
- `mount()` 会先 `await fontsReady()` 再 load / create，画布类编辑器首次绘制即可用导入的字体。

### 大编辑器的拆分方式

`index.js` 放类定义与生命周期，功能拆到同目录文件，通过 mixin 挂到原型上：

- `installXxx(Ed)` 风格：`export function installUI(Ed) { const P = Ed.prototype; P.foo = function () {...} }`（doc image slides video midi geo）
- 对象合并风格：`Object.assign(SheetEditor.prototype, Selection, Editing, Ops, ...)`（sheet）

新增功能时放进对应文件，**不要**把所有东西堆进 index.js。

---

## 5. 各编辑器速查

| kind | 入口类 | 数据模型 / 快照 | 关键文件 |
| --- | --- | --- | --- |
| image | `ImageEditor` | `ImageDoc`：图层各持有 canvas，**写时复制**——改像素前 `doc.writable(layer)`；快照共享未修改图层 | doc.js 模型；canvas.js 视图与指针；tools.js 工具定义与默认选项；ops.js 图层 / 选区 / 变换；filters.js 调整与滤镜；panels.js；menus.js；psd.js（ag-psd） |
| geo | `GeoEditor` | `Scene`：对象列表 + 依赖拓扑求值；快照为 JSON 字符串 | model.js 对象类型与计算；scene.js 求值 / 删除 / 代数视图；tools.js 作图工具；render.js 画布与 SVG 导出；interact.js；expr.js 表达式；conic.js 圆锥曲线；input.js 输入栏；samples.js |
| doc | `DocEditor` | contenteditable 的 `this.body` + `this.page`（纸张、边距、字体）；快照 = innerHTML + page | ui.js 工具栏 / 页面设置；features.js 插入对象、表格、公式、目录、查找替换；convert.js MD/DOCX→HTML；docx.js HTML→DOCX；latex-in.js / latex-out.js |
| sheet | `SheetEditor` | `Sheet` + `CellStore`（64 行分块，写时复制）；公式引擎 `formula/`（lexer → parser → evaluate，engine 管依赖与重算） | grid.js 虚拟画布表格；render.js；format.js 样式与字体；numfmt.js；io*.js 读写 XLSX/ODS/CSV/PDF；chart.js；`node src/editors/sheet/formula.test.mjs` 单元测试 |
| slides | `SlidesEditor` | `deck` 纯 JSON（结构注释见 model.js 头部）；快照为 JSON 字符串 | render.js DOM 渲染；interact.js 拖拽 / 参考线；ui.js 工具栏；panels.js；present.js 放映；pptx.js 导出；import-pptx.js 导入；css.js 幻灯片 CSS |
| video | `VideoEditor` | `proj` 纯 JSON（media / tracks / clips）；媒体字节与解码器在 `editor.assets / blobs`，不进快照；`.lvideo` = zip(project.json + 内嵌媒体) | media.js（mediabunny 探测 / 解码）；preview.js；timeline.js；render.js 帧合成（预览与导出共用）；export.js 逐帧编码 MP4/WebM/音频 |
| midi | `MidiEditor` | `song`（结构注释见 smf.js 头部）；快照 structuredClone | smf.js SMF 读写；roll.js 钢琴卷帘；tracks.js；audio.js（spessasynth 实时播放）；render-worker.js 离线渲染 WAV；音色库 `public/soundfonts/GeneralUserGS.sf3` |

截图 / 录屏：`src/tools/capture.js`（`takeScreenshot`、`Recorder`）+ `electron/capture.js` + `shot.html / recbar.html`。全局快捷键 Ctrl+Alt+A / F / R / P。

---

## 6. 常见修改的落点

| 需求 | 修改位置 |
| --- | --- |
| 新增一种文件格式（打开） | `core/files.js` 的 `KINDS[kind].exts`；编辑器 `load()` 按 ext 分支；如需系统关联再改 `package.json > build.fileAssociations` |
| 新增保存 / 导出格式 | 编辑器 `formats()`（无损，同时加进 `KINDS.native`）或 `exports()` |
| 新增菜单命令 / 快捷键 | 编辑器 `menus()` 里加菜单项并写 `key`，自动注册快捷键，也自动出现在命令面板中 |
| 新增全局快捷键 | `src/main.js` 的 `handleKey()`；需要跨应用生效的放 `electron/capture.js` 的 `registerHotkeys` |
| 新增全局命令（命令面板） | `src/main.js` 的 `globalCommands()` |
| 新建模板 | `src/main.js` 的 `TEMPLATES` + 编辑器 `create(options)`；主页缩略图 `tplThumb()` 用 CSS 画 |
| 新增设置项 | `core/store.js` 的 `DEFAULT_SETTINGS` + `src/main.js` 的 `renderSettings()` |
| 编辑器私有偏好（画笔大小等） | `store.getPref('ns', 默认值) / setPref` |
| 新增编辑器类型 | `KINDS` + `src/main.js` 的 `LOADERS` 与 `TEMPLATES` + `src/editors/<kind>/index.js` + `src/styles/<kind>.css`（在 main.js 顶部 import）+ `test/<kind>.mjs` + `vite.config.js` 的 `CLASSES` |
| 主进程能力 | 见 §2 末尾 |
| 字体下拉框 | 统一用 `fontSelect()`，见 §7 |

---

## 7. 字体系统

- 导入的字体复制到 `userData/fonts/`，启动时 `initFonts()` 用 `FontFace` 注册（`media://` URL），DOM 与 canvas 都可以直接用 family 名。
- `electron/fonts.js` 解析 name 表：`family`（英文，作 CSS 名）、`label`（中文名优先，用于显示）、`weight / style`（OS/2）。WOFF2 读不出名称，退回文件名。
- 字体下拉框：`fontSelect(内置选项, 值, onchange, { fmt, stackOf, title, width })`
  - `fmt: 'css'`（默认）值形如 `'"Family", sans-serif'`（doc / slides / image）；`fmt: 'name'` 值为 `'Family'`（sheet / video）。
  - 自动分组“内置 / 导入的字体 / 系统字体 / 更多（导入字体…）”，字体增删后自动刷新；当前值不在列表中时显示在“当前字体”组。
  - `stackOf` 把选项值换算为 CSS font-family，用于系统字体去重（sheet 传 `fontFamily`）。
- 表单对话框里用 `fontOptions(内置, { importItem: false, current })`。
- 导出：PDF / 打印由主进程自动注入 `@font-face`；SVG foreignObject 栅格化（如 slides 导出 PNG）需调用 `embedFontCSS(文本)` 以 data URL 内嵌；DOCX 只写字体名，不嵌入。

---

## 8. 构建、运行、测试

```bash
npm install                 # postinstall 复制 KaTeX 到 public/vendor
npm start                   # vite build && electron .
npm run build               # 仅构建到 dist/
node scripts/run-smoke.mjs <name...>   # 冒烟测试；不带参数跑全部 test/*.mjs
node src/editors/sheet/formula.test.mjs
npm run dist                # 打包 NSIS 安装程序到 release/
```

> 注意：`package.json` 的 `npm run dev` 引用的 `scripts/dev.mjs` **目前不存在**，开发时用 `npm start`，或自行补写 dev 脚本（Vite 端口 5199，主进程读取 `VITE_DEV_SERVER_URL`）。

### 冒烟测试

- 每个测试构建到独立目录 `.tmp/dist-<名>`、使用独立用户数据 `.tmp/userdata-<名>`，**可以并行**运行多个。
- 窗口 1440×900；截图保存到 `.tmp/smoke/<名>/`，用图片查看工具检查界面。
- 测试函数参数：`{ js, shot, wait, key, mouse, drag, click, type, log, outDir, theme }`。
  - `js(code)` 的 code 是**函数体**：要取值必须写 `return`；返回值必须可结构化克隆（不要直接返回编辑器实例，写成 `window.app.newDoc('doc').then(() => true)`）。
- 页面中：`window.app.newDoc(kind, options)` 返回编辑器；`window.app.active.editor` 为当前编辑器；`window.app.openPaths([绝对路径])`；保存用 `editor.writeTo('.tmp/...')`。
- `SMOKE_STUB=sheet,image` 可把指定编辑器替换为空实现（vite.config.js）。
- 现有测试：shell doc geo image sheet slides video midi capture fonts；`probe.mjs` 仅探测编解码器支持，不是回归测试。

**修改后至少运行：受影响编辑器的测试 + `shell`；动到 core/ 或 base.js 时全部运行。**

### CML 打包（共享 Electron 运行时）

CML 以 `apps\runtime\electron.exe apps\liteeditor\app` 启动本应用（`app.isPackaged === false`、未设置 `VITE_DEV_SERVER_URL` → 走 `app://` 生产路径，根目录为 `<app>/dist`）。
`electron/main.js` 开头显式 `app.setName('LiteEditor')`、`userData = %APPDATA%\LiteEditor`、`setAppUserModelId('com.liteeditor.app')`，
因此数据目录与单实例锁和独立安装版一致。暂存由 CML 仓库的 `apps/build-apps.ps1` + `apps/stage-app.mjs` 完成，输出 `out/app`（electron/ dist/ build/icon.png + 精简 package.json）。
冒烟测试的 `theme('dark'|'light'|{...})` 写入临时 `CML_THEME_FILE`，走真实的主题桥。

### 打包与网络

直连 GitHub 下载 Electron 可能超时，使用镜像：

```bash
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/ npm run dist
```

推送 GitHub 若直连失败，本机系统代理为 `127.0.0.1:7897`：

```bash
git -c http.proxy=http://127.0.0.1:7897 -c http.sslBackend=openssl push
```

---

## 9. 约定与陷阱

- 所有 UI 文本中文；图标只用 lucide（名称用 kebab-case，拼错会得到空图标）。
- 右键菜单用 `contextMenu(e, items)`；全局已阻止非输入区域的系统右键菜单。
- 编辑器内部要接管文件拖放（如把图片拖进文档），在目标元素上加 `data-drop` 属性，外壳就不会弹出“打开文件”遮罩。
- 快照要便宜：大对象共享引用或使用 JSON 字符串（JS 引擎会共享相同字符串），像素数据写时复制。
- 模态对话框打开时外壳不处理全局快捷键；菜单打开时 Esc 先关菜单。
- Windows 路径：拼接用 `\\`（基类里另存为默认路径就是这样拼的）；`media://` 路径必须 `encodeURIComponent`。
- 仓库中文件以 CRLF 存在工作区，git 提交时会转换为 LF，提示信息可忽略。
- 新增依赖直接 `npm install`，但注意安装包体积；运行时静态资源放 `public/`，需从 node_modules 复制的加到 `scripts/prepare-assets.mjs`。
