# LiteEditor

轻量全能编辑器 —— 一个应用，修图、尺规作图、写文档、做表格、做演示。

基于 Electron + Vite 构建（与 LiteReader 同一套界面框架），所有文件均在本地处理。作为 CML 启动器的内置应用发布，界面配色跟随 CML 主题。

## 编辑器

| 编辑器 | 对标 | 打开 | 保存（无损） | 导出 |
| --- | --- | --- | --- | --- |
| 图像编辑 | Photoshop | PSD、PNG、JPG、WEBP、BMP、GIF、AVIF、SVG | PSD（保留图层） | PNG、JPG、WEBP |
| 几何画板 | 几何画板 / GeoGebra | LGEO | LGEO | PNG、SVG |
| 文字处理 | Word / LaTeX | DOCX、TEX、MD、HTML、TXT、LDOC | LDOC、DOCX、TEX、HTML、MD | PDF、TXT |
| 电子表格 | Excel | XLSX、XLS、ODS、CSV、TSV、LSHEET | LSHEET、XLSX、ODS | CSV、PDF、HTML |
| 演示文稿 | PowerPoint | LSLIDE、PPTX | LSLIDE | PPTX、PDF、PNG、ZIP |

### 功能概览

- **图像编辑**：图层（16 种混合模式、不透明度、蒙版、锁定、拖动排序）、矩形 / 椭圆 / 套索 / 多边形套索 / 魔棒选区（加减交、羽化、扩展收缩、反选）、画笔 / 铅笔 / 橡皮擦 / 仿制图章 / 模糊锐化 / 减淡加深 / 涂抹、油漆桶、渐变（线性 / 径向 / 角度 / 对称）、文字图层（可再编辑）、形状、吸管、自由变换（缩放 / 旋转 / 移动）、裁剪、画布与图像大小、旋转翻转；调整（亮度对比度、色阶、曲线、色相饱和度、色彩平衡、曝光度、自然饱和度、黑白、照片滤镜、渐变映射、反相、去色、阈值、色调分离、色调均化、自动对比度，均带实时预览）；滤镜（高斯 / 动感模糊、USM 锐化、杂色、中间值、马赛克、彩色半调、浮雕、查找边缘、素描、油画、暗角）；历史记录面板。
- **几何画板**：构造式依赖图（拖动自由点，所有对象实时更新）、点 / 交点 / 中点 / 线段 / 射线 / 直线 / 向量 / 平行线 / 垂线 / 中垂线 / 角平分线 / 切线 / 圆 / 圆弧 / 多边形 / 正多边形、平移 / 旋转 / 反射 / 位似、轨迹、度量（距离、长度、角度、面积、周长、斜率、坐标、方程）与计算、参数滑块与动画、追踪、函数图像（y = f(x)、参数方程、极坐标、导函数）、代数视图、PNG / SVG 导出。
- **文字处理**：A4 分页视图、字体字号（中文字号）、段落样式、对齐 / 行距 / 缩进、列表与任务列表、表格（合并 / 拆分 / 底纹 / 边框）、图片（拖动缩放、题注）、LaTeX 公式、目录、脚注、分页符、查找替换（正则）、格式刷、Markdown 快捷输入、源码视图（Markdown / HTML / LaTeX 与可视化编辑实时同步）、页面设置、字数统计。**LaTeX**：打开 .tex 后可视化编辑（章节编号、公式与交叉引用、定理 / 证明、图表浮动体、参考文献、脚注），保存时保留原导言区与 `\label` / `\ref` / `\cite`。
- **电子表格**：虚拟滚动（百万行级）、冻结窗格、100+ 函数的公式引擎（跨表引用、依赖重算、循环检测、引用着色与点选、函数补全与参数提示）、填充柄序列、数字格式、边框与合并、条件格式（规则 / 数据条 / 色阶）、排序筛选、查找替换、删除重复项、分列、数据验证、图表（柱形 / 条形 / 折线 / 面积 / 饼 / 圆环 / 散点）、多工作表。
- **演示文稿**：文本 / 形状（25 种）/ 图片 / 表格 / 图表 / 公式 / 图标、智能参考线、对齐分布与层次、组合锁定、8 款设计主题与背景、版式、9 种切换效果、8 种对象动画与动画窗格、放映（黑屏 / 白屏、页码跳转）与演讲者视图、备注。

各编辑器共享：多标签页、菜单栏与快捷键、撤销 / 重做与历史记录、未保存提示、自动保存（可选）、拖放打开、最近文件。

## 开发

```bash
npm install            # 安装依赖（postinstall 会把 KaTeX 样式与字体复制到 public/vendor）
npm run dev            # 开发模式（Vite 热更新 + Electron）
npm start              # 构建后以生产模式运行
npm run dist           # 打包 Windows 安装程序（输出到 release/）
node scripts/run-smoke.mjs [image|geo|doc|sheet|slides|shell]   # 冒烟测试，截图输出到 .tmp/smoke/
node src/editors/sheet/formula.test.mjs                          # 公式引擎单元测试
```

国内网络可使用镜像：

```bash
set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
set ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/
```

## 主题

主题跟随 CML 启动器，在 CML 设置 → 外观 中切换（应用内不再提供主题选择）。

- 主进程 `electron/theme-bridge.js` 按 `CML_THEME_FILE` → `%APPDATA%\CML\theme.json` → 内置默认配色（浅色，主色 `#4fa3d9`）的顺序读取主题，
  监视所在目录（CML 先写 `theme.json.tmp` 再重命名，150ms 防抖），变化后推送给所有窗口；解析失败时保持当前配色。
- 渲染进程 `src/core/theme.js` 把基础色写到 `--bg --surface --text --accent --accent-2 --on-accent --paper --ink --art-*`，其余色彩由 `base.css` 的 `color-mix` 推导；
  `nativeTheme.themeSource` 跟随 `dark`。文档纸张、画布内容保持真实颜色。
- 协议见 CML 仓库 `docs/THEME_BRIDGE.md`。

## CML 打包

CML 只附带一份共享的 Electron 运行时，以 `apps\runtime\electron.exe apps\liteeditor\app` 启动本应用。
在 CML 仓库运行 `powershell -File apps\build-apps.ps1`：vite 构建后把 `electron/ dist/ build/icon.png` 与精简的 `package.json` 放到 `out/app`
（渲染进程依赖已由 vite 打包，主进程只用 Node 内置模块，无需 node_modules）。
应用名、AppUserModelId（`com.liteeditor.app`）与数据目录（`%APPDATA%\LiteEditor`）在主进程中显式设置，与独立安装版一致，单实例锁按应用区分。

## 通用快捷键

| 快捷键 | 功能 |
| --- | --- |
| Ctrl+N / Ctrl+O | 新建（当前类型）/ 打开 |
| Ctrl+S / Ctrl+Shift+S | 保存 / 另存为 |
| Ctrl+Z / Ctrl+Y（Ctrl+Shift+Z） | 撤销 / 重做 |
| Ctrl+W / 中键点击标签 | 关闭标签 |
| Ctrl+Tab / Ctrl+Shift+Tab | 切换标签 |
| F11 | 全屏 |

各编辑器的专用快捷键显示在菜单项右侧与工具提示中。

## 目录结构

```
electron/          主进程（窗口、app:// 与 media:// 协议、文件读写、HTML → PDF / 打印）
src/core/          主题桥（跟随 CML）、存储、文件类型、DOM 工具、菜单系统、撤销栈
src/editors/       base.js 编辑器基类；image / geo / doc / sheet / slides 各编辑器
src/styles/        样式
scripts/           资源准备、开发启动、冒烟测试
test/              冒烟测试脚本
ARCHITECTURE.md    编辑器实现约定
```
