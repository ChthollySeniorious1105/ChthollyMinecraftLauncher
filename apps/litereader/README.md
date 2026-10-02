# LiteReader

轻量全能阅读器 —— 一个应用，读遍电子书与文档，听音乐、看图片与视频、浏览压缩包。

基于 Electron + Vite 构建，所有格式均在本地解析，无需安装任何额外软件。

## 支持的格式

| 类别 | 格式 | 实现 | 主要功能 |
| --- | --- | --- | --- |
| 电子书 | EPUB、MOBI、AZW3、AZW、FB2、CBZ | foliate-js | 分页 / 滚动、双栏、目录、书签、全文搜索、进度记忆 |
| PDF | PDF | pdf.js | 虚拟化渲染、缩略图、目录、搜索高亮、文本选择、旋转、双页、夜间反色、加密 PDF |
| Word | DOCX / DOC | docx-preview / word-extractor | DOCX 保留原排版；DOC 提取正文后以阅读模式排版 |
| 演示文稿 | PPTX、PPSX、POTX、PPTM、PPT、ODP | JSZip + 自研渲染 | 母版 / 版式 / 主题继承、形状与渐变、图片裁剪、表格、SmartArt、音视频、缩略图、大纲、备注、搜索、全屏放映（F5） |
| 网页 | HTML、XHTML、MHT / MHTML | 沙箱 iframe | 原始 / 阅读 / 源码三种视图、相对路径资源、MHT 归档内资源、文档结构、页内查找；脚本与网络请求一律禁用 |
| LaTeX | TEX、LATEX、LTX | 自研转换 + KaTeX | 多文件工程（自动合并 \input / \include，读取 .bib 参考文献并按 plain 样式排版）、章节编号与目录、公式编号与交叉引用、定理 / 证明、列表、表格、插图（含 PDF 插图）、脚注、参考文献、自定义宏；可切换源码 |
| 富文本 | RTF、ODT | rtf.js / 自研 | 保留原格式（颜色、字号、对齐、表格、图片），可切换统一阅读排版 |
| 版式文档 | OFD、XPS / OXPS、DjVu | 自研 / djvu-rs (WASM) | 矢量渲染、缩略图、页码跳转、文字查找；DjVu 支持文字层 |
| 帮助文档 | CHM | Windows hh.exe | 目录树、索引筛选、前进 / 后退、页内查找 |
| 表格 | XLSX、XLS、XLSB、ODS、CSV、TSV | SheetJS | 虚拟滚动（数十万行流畅）、多工作表、单元格查找、公式查看 |
| 文本 | TXT、Markdown、代码 / 日志等 | 自研 + highlight.js + KaTeX | 编码自动识别（UTF-8 / GBK / Big5 / Shift_JIS…）、章节自动识别、代码语法高亮与行号、Markdown 数学公式 |
| 音乐 | MP3、OGG、WAV、FLAC、M4A、AAC、OPUS、MID / MIDI | Web Audio + SpessaSynth | 播放列表、LRC 歌词同步、封面 / 标签读取、5 种可视化、MIDI 使用 GeneralUser GS 音色库合成 |
| 图片 | PNG、JPG、JPEG、BMP、GIF、WEBP、AVIF、SVG、ICO | 原生 | 缩放 / 拖拽、旋转、翻转、幻灯片、胶片栏、同目录切换 |
| 压缩包 | ZIP、7Z、RAR（v4/v5）、TAR、GZ、CBR、CB7 等 | libarchive (WASM) | 网格 / 列表视图、图片画廊式预览、加密包输入密码、直接打开包内文件 |
| 视频 | MP4、WEBM、MKV、MOV、OGV | 原生 `<video>` | 倍速、画中画、SRT / VTT 字幕（自动加载同名字幕）、截图、进度记忆 |

> 视频播放依赖 Chromium 内置解码器：H.264 / VP8 / VP9 / AV1 + AAC / Opus / MP3 均可播放；HEVC 取决于系统硬件解码支持。
> 带 DRM 的 Kindle 书籍无法打开。
>
> 近似显示提示：旧版 PPT 与 ODP 仅提取文字大纲；PPTX 中的图表、特殊形状，网页中的脚本 / 远程资源，LaTeX 中的 TikZ、EPS 图片、外部 .bib 等无法原样还原的内容，会在工具栏显示 ⚠ 按钮，点击可查看具体说明。CHM 解析依赖 Windows 自带的 hh.exe。

## 格式转换

文件打开后，工具栏右侧的「打印 / 导出 / 转换」菜单可以转换当前文件；左侧栏的「转换」页面支持批量转换（拖入多个不同格式的文件，按类型分别选择目标格式）。

| 源类型 | 可转换为 |
| --- | --- |
| 文档（TXT、Markdown、代码、DOCX、DOC、RTF、ODT、HTML、MHT、LaTeX、EPUB / MOBI / AZW3、CHM） | PDF、DOCX、HTML、Markdown、TXT、EPUB |
| 版式页面（PDF、PPTX / PPT / ODP、OFD、XPS、DjVu、CBZ、图片） | PDF、PNG、JPEG、WebP、BMP、HTML、TXT、DOCX |
| 表格（XLSX、XLS、ODS、CSV…） | XLSX、XLS、ODS、CSV、TSV、JSON、HTML、PDF、TXT |
| 音频（MP3、OGG、WAV、FLAC、M4A、MIDI…） | WAV、MP3 |
| 压缩包（ZIP、7Z、RAR、TAR…） | ZIP、7Z、TAR、TAR.GZ |

每个目标格式都标明 **无损 / 有损**，有损时列出具体丢失的内容（例如「Markdown 不支持字体、颜色、对齐等样式」「MP3 为有损压缩」「源文件已是有损格式，转为 WAV 不会恢复音质」）。

## 打印与导出 PDF

所有文档、页面与表格类文件都可以打印（Ctrl+P）或导出为 PDF（Ctrl+Shift+E）：

- 回流文档（文本、Markdown、Word、网页、LaTeX、电子书等）按纸张重新排版，可选纸张大小、方向、边距与页眉页脚（标题 / 页码）
- 版式文档（PDF、演示文稿、OFD、XPS、DjVu、图片）按原始页面尺寸逐页输出，可指定页码范围（如 `1-3,5`）
- 导出的 PDF 带书签大纲与可选择的文字（矢量页面）

## 主题

主题跟随 CML 启动器，在 CML 设置 → 外观 中切换（应用内不再提供主题选择，也没有 Ctrl+T 明暗切换）。
阅读区默认「跟随主题」使用 CML 主题的纸张 / 墨色（`paper` / `ink`），也可在阅读设置中单独选择纸张颜色（纯白、暖黄、羊皮、护眼绿、夜间、纯黑等）。

- 主进程 `electron/theme-bridge.js` 按 `CML_THEME_FILE` → `%APPDATA%\CML\theme.json` → 内置默认配色的顺序读取主题，监视所在目录
  （CML 先写 `theme.json.tmp` 再重命名，150ms 防抖），变化后推送给所有窗口；解析失败时保持当前配色。`nativeTheme.themeSource` 跟随 `dark`。
- 渲染进程 `src/core/theme.js` 把基础色写到 CSS 变量，其余色彩由 `base.css` 的 `color-mix` 推导。协议见 CML 仓库 `docs/THEME_BRIDGE.md`。

## CML 打包

CML 只附带一份共享的 Electron 运行时，以 `apps\runtime\electron.exe apps\litereader\app` 启动本应用。
在 CML 仓库运行 `powershell -File apps\build-apps.ps1`：vite 构建后把 `electron/ dist/ build/icon.png`、精简的 `package.json`，
以及主进程运行时加载的 `word-extractor`、`music-metadata` 及其依赖放到 `out/app`（其余依赖已由 vite 打包）。
应用名、AppUserModelId（`com.litereader.app`）与数据目录（`%APPDATA%\LiteReader`）在主进程中显式设置，单实例锁按应用区分。

## 开发

```bash
npm install            # 安装依赖（postinstall 会把 worker / wasm 等资源复制到 public/vendor）
npm run dev            # 开发模式（Vite 热更新 + Electron）
npm start              # 构建后以生产模式运行
npm run dist           # 打包 Windows 安装程序（输出到 release/）
npm run test:latex     # LaTeX 转换单元测试
npm run smoke -- samples/slides.pptx samples/paper.tex   # 在真实窗口中打开样例并截图到 test-output/smoke/
npm run smoke          # 不带文件：主页 / 设置页截图，并用临时 CML_THEME_FILE 验证浅色 → 深色主题跟随
npm run test:convert   # 51 条转换路线的端到端测试，输出到 test-output/convert/
npm run test:ui        # 打印 / 转换界面测试
```

国内网络可使用镜像：

```bash
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
set ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
```

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| Ctrl+O | 打开文件 |
| Ctrl+W / 中键点击标签 | 关闭标签 |
| Ctrl+Tab / Ctrl+Shift+Tab | 切换标签 |
| F11 | 全屏 |
| ← / → / 空格 / PageUp / PageDown | 翻页、上一张 / 下一张、快退 / 快进 |
| Ctrl+P / Ctrl+Shift+E | 打印 / 导出 PDF |
| Ctrl+F | 搜索（电子书 / PDF / 表格 / 演示文稿 / 网页 / LaTeX） |
| F5 / Shift+F5 | 演示文稿从头 / 从当前页放映（放映中 B 黑屏、W 白屏、Esc 退出） |
| N | 演示文稿显示 / 隐藏备注 |
| Ctrl+U | 网页 / LaTeX 切换源码 |
| Ctrl + 滚轮 / Ctrl +/- / Ctrl 0 | 缩放 |
| B | 电子书添加书签 |
| R / S | 图片旋转 / 幻灯片 |
| 空格 / M / ↑↓ | 播放暂停 / 静音 / 音量 |
| 0-9 | 视频跳转到 0%-90% |
| [ / ] | 视频减速 / 加速 |
| Ctrl+S | 视频截图 |

## 目录结构

```
electron/          主进程（窗口、自定义协议 media:// 支持 Range 流式读取、DOC 解析、音频元数据）
src/core/          主题桥（跟随 CML）、存储、文件类型、编码识别、DOM 工具
src/core/pptx.js   PPTX 解析与渲染；src/core/latex.js  LaTeX → HTML 转换；src/core/find.js  通用页内查找
src/core/formats.js PPT / RTF / ODT / ODP / OFD / XPS 解码；src/core/convert.js 格式转换引擎；src/core/print.js 打印与导出 PDF
src/viewers/       各格式查看器（ebook / pdf / docs / text / sheet / slides / web / tex / image / audio / video / archive）
src/styles/        样式
public/soundfonts/ MIDI 音色库（GeneralUser GS，SF3）
scripts/           资源准备、开发启动、样例生成（make-*-sample.py）、测试（test-latex.mjs、smoke.mjs）
samples/           各格式的测试样例文件
```
