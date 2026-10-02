# LiteReader 架构说明

面向后续开发（人或 AI 会话）的快速上手文档：先读本文，再按「常见修改」一节定位文件。
功能与格式清单见 `README.md`，此处只讲结构与约定。

## 技术栈

- **Electron 44**（主进程 ESM，`electron/main.js`）+ **Vite 8**（渲染进程，原生 ES 模块，无框架）
- UI 由自研的轻量 DOM 工具 `h()` 构造（`src/core/dom.js`），图标用 `lucide`（`src/core/icons.js`）
- 所有格式都在本地解析，依赖见 `package.json`；需要 worker / wasm 的库由 `scripts/prepare-assets.mjs`（postinstall）复制到 `public/vendor/`（已忽略，不提交）
- 界面文字与代码注释统一使用**中文**

## 目录总览

```
electron/
  main.js          主进程：窗口、自定义协议、全部 IPC 处理（文件读写、对话框、打印/PDF、截图、CHM、DOC、音频元数据）
  preload.cjs      contextBridge 暴露 window.lite（渲染进程访问系统能力的唯一入口）与 window.cmlTheme（主题）
  theme-bridge.js  CML 主题桥：读取 / 监视 theme.json，推送 cml-theme:changed，同步 nativeTheme
index.html         页面骨架：#titlebar #tabs #rail #home #settings-page #convert-page #viewers #toasts
src/main.js        App 类：标签页、页面切换、打开文件、主页 / 设置页、全局快捷键、拖放
src/core/          与界面无关的公共模块（见下表）
src/viewers/       每种文件类型一个查看器，均继承 viewers/base.js 的 Viewer
src/styles/        base.css（变量）/ app.css（外壳布局）/ viewers.css（查看器）/ formats.css（查找栏、提示、转换、打印界面）
scripts/           开发启动、资源准备、测试脚本、样例生成脚本（Python）
samples/           各格式的测试样例（测试脚本直接引用）
public/            logo、MIDI 音色库 soundfonts/GeneralUserGS.sf3
build/icon.png     打包图标
```

## 进程与安全模型

- 主窗口 `frame: false`（自绘标题栏），`contextIsolation + sandbox`，**渲染进程没有 Node**。需要系统能力时：
  1. 在 `electron/main.js` 的 `registerIpc()` 中加 `ipcMain.handle('xxx:yyy', ...)`
  2. 在 `electron/preload.cjs` 的 `window.lite` 上加对应方法
  3. 主进程主动推送的事件必须加入 preload 中 `on()` 的 `allowed` 白名单
- 自定义协议：
  - `app://local/...` 生产模式下服务 `dist/`（开发模式直接用 Vite 地址，由 `VITE_DEV_SERVER_URL` 决定）
  - `media://file/<encodeURIComponent(绝对路径)>` 读本地文件，支持 Range（音视频拖动）
  - `media://local/D:/dir/file` 保留目录层级，供网页 / LaTeX 的相对路径资源使用
  - 渲染端用 `files.js` 的 `mediaURL()` / `localURL()` / `localDirURL()` 生成，不要手拼
- 外链一律交给系统浏览器；页面内导航被阻止。
- 单实例：再次双击文件时通过 `app:open-files` 发给已有窗口；启动参数中的文件由 `app:take-files` 取走。

## 渲染进程核心流程

```
打开文件（对话框 / 拖放 / 最近列表 / 启动参数）
  → App.openPaths(paths) → typeOf(path) 得到类型键
  → Source.fromPath(path, size)
  → App.openSource(source)
      → LOADERS[type]() 动态 import 对应查看器（按需加载）
      → new Viewer(source, app)，append 到 #viewers，创建标签
      → await viewer.mount()；失败时 viewer.error(e)
      → viewer.addOutputMenu()（打印 / 导出 PDF / 转换 菜单）
```

- **类型注册表**：`src/core/files.js` 的 `TYPES`（名称、图标、颜色、扩展名）。扩展名 → 类型键 → 查看器，一条链路。
- **Source**（`files.js`）：统一文件来源，可以是磁盘路径，也可以是压缩包内的 Blob（`Source.fromBlob`，带 `parent`）。
  用 `source.arrayBuffer()` / `blob()` / `file()` / `url()` 读取，不要直接 fetch 路径。`source.key` 用于存进度。
- **标签页规则**：同一路径只开一个标签；音乐只保留一个播放器标签（切歌走播放列表）；多选图片 / 音乐 / 视频只开第一个，其余靠同目录切换（`siblings()`）。
- **快捷键**：`App.handleKey` 先处理全局键（Ctrl+O/W/Tab/T/P、Ctrl+Shift+E、F11），然后交给当前查看器的 `onKey(e)`，返回 `true` 表示已处理。

## 查看器（src/viewers/）

基类 `Viewer`（`base.js`）提供骨架：`el` > `toolbar(left/center/right)` + `main(sidebar, content)`。

| 生命周期 / 工具 | 说明 |
| --- | --- |
| `mount()` | 异步加载并渲染内容（子类实现） |
| `onShow()` / `onHide()` | 标签切换时调用（暂停播放、重算尺寸等） |
| `onKey(e)` | 返回 true 表示消费了按键 |
| `destroy()` | 执行所有 disposer 并移除 DOM |
| `listen(target, type, fn)` / `onDispose(fn)` | **注册事件务必用这两个**，销毁时自动清理 |
| `addTitle()` / `tool()` / `sep()` | 工具栏标题与按钮 |
| `loading()` / `error()` | 加载态与错误态 |
| `setCaveats([...])` | 无法原样还原时在工具栏显示 ⚠ 说明 |
| `printable()` / `canPrint` | 打印内容，默认走 `core/print-source.js` |
| `sidebarTabs()` | 通用侧栏标签页组件 |

继承关系：

```
Viewer
├─ EbookViewer (ebook.js, foliate-js)      ├─ PdfViewer (pdf.js)
├─ SheetViewer (sheet.js, SheetJS)          ├─ SlidesViewer (slides.js, core/pptx.js + formats.js OutlineDeck)
├─ WebViewer (web.js, 沙箱 iframe + MHT)     ├─ PagedViewer (paged.js, OFD/XPS/DjVu)
├─ ChmViewer (chm.js, 主进程 hh.exe 解包)    ├─ ImageViewer / AudioViewer / VideoViewer / ArchiveViewer
└─ ScrollDocViewer (docs.js, 滚动 + 缩放 + 进度)
   ├─ DocxViewer (docx-preview)
   └─ FlowTextViewer (回流阅读排版)
      ├─ TextViewer / DocViewer (text.js)   ├─ RichViewer (rich.js, RTF/ODT)
      └─ TexViewer (tex.js, core/latex.js)
```

辅助模块：`reader-style.js`（阅读字体 / 纸张 / 排版面板）、`convert-ui.js`（转换对话框与批量转换页）、`core/find.js`（通用页内查找 `DomFinder` + `findBar`）。

## core/ 模块

| 文件 | 职责 |
| --- | --- |
| `dom.js` | `h()`、`btn`、`toast`、`popover/menu`、`prompt`、`slider/segmented/toggle`、格式化函数 |
| `files.js` | 类型注册表、`Source`、路径工具、`media://` 地址 |
| `store.js` | localStorage 持久化：设置（`DEFAULT_SETTINGS`）、最近打开、阅读进度（上限 500 条） |
| `theme.js` | CML 主题桥（渲染端）：`initTheme()` 取 `window.cmlTheme` 的主题并订阅变化，`applyTheme` 写基础色 CSS 变量（派生色由 `color-mix` 推导）并派发 `themechange`；`currentTheme()` 供阅读配色（`reader-style.js` 的「跟随主题」纸张）使用 |
| `encoding.js` | 文本编码识别（jschardet）与解码 |
| `formats.js` | 解码器：PPT、RTF、ODT/ODP、OFD、XPS；`OutlineDeck`（纯文字幻灯片） |
| `pptx.js` | PPTX → 绝对定位 HTML 幻灯片（母版/版式/主题、形状、表格、图片…），`lossy` 集合记录近似项 |
| `latex.js` | LaTeX → HTML（KaTeX 公式、编号、交叉引用、BibTeX）；纯函数，可在 Node 里测 |
| `convert.js` | 格式转换引擎（见下） |
| `print.js` / `print-source.js` | 打印对话框、执行打印 / 导出；各类型的打印内容生成 |
| `sevenzip.js` / `crc32.js` | 最小 7z 写出器（仅存储模式） |

## 格式转换引擎（core/convert.js）

「输入 → 中间表示 → 写出器」三段式：

- `KIND`：类型键 → 中间表示（`doc` 回流文档 / `pages` 固定页面 / `sheet` / `audio` / `archive`）
- `OUTPUTS`：中间表示 → 可用目标；`TARGETS`：目标格式元数据
- `toDoc(source)` → `{ title, html, css? }`；`toPages(source)` → `{ pages: [{ w, h, image(scale), text?() }], dispose }`
- `lossInfo()`：每条路线的**有损说明**，界面据此显示「有损」及原因。新增路线时必须补充
- `convert(source, { target, ... })` 返回 `[{ name, data }]`（多页 / 多表可返回多个文件）

打印复用同一套中间表示：`doc` 由 Chromium 按纸张重新分页；`pages` 按原尺寸逐页（`cssPage: true`）。
主进程 `print:html` 在隐藏窗口加载 HTML，模式为 `print`（系统打印对话框）/ `pdf`（写文件）/ `preview`（返回字节，转换 PDF 时使用）。
`render:png` 用于把 HTML 页面截图为图片。

## 常见修改

**新增一种文件格式（已有查看器能处理）**：在 `files.js` 的 `TYPES[x].exts` 加扩展名 → 在对应解码处（如 `formats.js`、查看器 `mount()`、`convert.js` 的 `toDoc/toPages`）处理该扩展名 → 同步 `package.json` 的 `build.fileAssociations` → 更新 README 表格。

**新增一类查看器**：
1. `files.js` 的 `TYPES` 加类型键
2. 新建 `src/viewers/xxx.js`，`export class XxxViewer extends Viewer`（或 `FlowTextViewer` / `ScrollDocViewer`），实现 `mount()`
3. `src/main.js` 的 `LOADERS` 注册；如需在主页显示，加入 `renderHome()` 的 `cats`
4. 可转换 / 可打印时在 `convert.js` 的 `KIND` 中映射，并在 `toDoc` / `toPages` 中实现
5. 样式写进 `viewers.css` 或 `formats.css`，只使用主题 CSS 变量（`--accent`、`--surface` 等），保证任意 CML 主题（浅色 / 深色）都适配

**新增转换目标**：`TARGETS` + `OUTPUTS` + 对应写出器（`writeDoc` / `writePages` / `writeSheet` / `writeAudio` / `writeArchive`）+ `lossInfo` 规则，然后跑 `npm run test:convert`。

**新增系统能力**：主进程 `registerIpc()` + `preload.cjs` 的 `window.lite`（见「进程与安全模型」）。

**新增设置项**：`store.js` 的 `DEFAULT_SETTINGS` 加默认值 → `main.js` 的 `renderSettings()` 加控件 → 在使用处用 `store.get()` / `store.onSettings()` 读取。

**主题**：跟随 CML 启动器（`CML_THEME_FILE` → `%APPDATA%\CML\theme.json` → 内置默认），应用内不提供主题选择；协议见 CML 仓库 `docs/THEME_BRIDGE.md`。阅读区纸张可在阅读设置中单独选择，默认 `readerPaper: 'theme'`。

## 开发与验证

```bash
npm install            # postinstall 复制 vendor 资源；国内网络见 README 的镜像设置
npm run dev            # Vite 热更新 + Electron（端口 5188）
npm start              # 构建后生产模式运行
npm run dist           # 打包 Windows NSIS 安装程序 → release/
```

测试都在真实 Electron 窗口中运行（会先 `vite build`），输出在 `test-output/`（已忽略）：

| 命令 | 内容 |
| --- | --- |
| `npm run test:latex` | 纯 Node：`samples/paper.tex` 的 LaTeX → HTML 检查 |
| `npm run smoke -- samples/xxx ...` | 打开样例、输出渲染报告并截图到 `test-output/smoke/` |
| `npm run test:convert` | 全部转换路线端到端（通过 `window.__convertTest`，定义在 `src/main.js` 末尾） |
| `npm run test:ui` | 打印 / 导出 / 转换界面流程截图 |

CML 以共享运行时 `apps\runtime\electron.exe apps\litereader\app` 启动本应用（`isPackaged === false`，未设 `VITE_DEV_SERVER_URL` 即走 `app://` → `dist/`）；
主进程开头显式设置应用名、`userData = %APPDATA%\LiteReader`、AppUserModelId，单实例锁按应用区分。暂存见 CML 仓库 `apps/build-apps.ps1`。
`npm run smoke` 不带文件时截取主页 / 设置页并经临时 `CML_THEME_FILE` 验证主题跟随；冒烟测试设置 `LITE_SMOKE`（跳过单实例锁）与独立的 `LITE_USERDATA`。

修改某个查看器后，至少用 `npm run smoke -- <对应样例>` 看一遍截图；改转换 / 打印时跑 `test:convert`。
样例缺失时可用 `scripts/make-*.py` 重新生成（需要 Python 及 odfpy、python-pptx 等库）。
调试：窗口内 F12 / Ctrl+Shift+I 打开开发者工具；`window.app` 是 App 实例。

## 约定与注意事项

- 缩进 4 空格，不写分号，单引号；注释简短、中文
- 查看器按需 `import()`，重量级库（pdf.js、docx、xlsx、katex…）不要在 `main.js` 顶层静态导入，以保证启动速度
- 画布导出前先把文件读成 Blob 再解码，直接用 `media://` 地址绘制会被标记为跨域而无法导出
- 网页内容在沙箱 iframe 中显示，脚本与网络请求被禁用（`web.js` 的 `sanitize()`）
- CHM 依赖 Windows 自带 `hh.exe`，只能在 Windows 上工作；缓存解包目录在 `%TEMP%/LiteReader/chm/`
- 打印临时文件在 `%TEMP%/LiteReader/print/`，每次启动清理
- `.gitattributes` 规定文本文件用 LF；Windows 下提交会有 CRLF 警告，属正常现象
- 版本号在 `package.json` 的 `version`，设置页「关于」读取 `app.getVersion()`
