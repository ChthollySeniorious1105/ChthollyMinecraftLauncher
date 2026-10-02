# DesktopPet 架构说明

Windows 桌面宠物（Electron 44，纯 HTML/CSS/JS，无打包器、无框架、无 TypeScript）。
一只宠物常驻桌面，托盘/双击打开「Hub」主窗口，里面是几十个工具页和小游戏。
UI 文案全部用简体中文。项目**不是 git 仓库**，改动前自己留意备份。

## 目录

```
src/
  main.js        主进程：窗口、数据存储、宠物养成/经济、成就、番茄钟、闹钟、剪贴板、键鼠看板、全部 IPC
  play.js        主进程玩法逻辑：每日任务 / 外出探险 / 钓鱼图鉴 / 宠物花园 / 扭蛋机（main.js 通过 init(deps) 注入）
  preload.js     contextBridge 暴露 window.api —— 渲染进程访问主进程的唯一通道
  pet/           桌面宠物窗口（透明置顶小窗）
  bongo/         键鼠映射看板悬浮窗（BongoCat 风格，uiohook-napi 全局输入）
  hub/           主窗口
    index.html     按顺序加载所有 CSS 和 <script>（新模块必须在这里登记）
    hub.js         Hub 框架：侧栏、路由、ctx、toast
    MODULES.md     模块契约（新页面必读）
    tools.js       首页（含首页磁贴列表）/ 番茄钟 / 待办 / 便签 / 换宠物 / 设置
    tools2.js      照顾宠物（商店、食物 SVG）/ 闹钟 / 白噪音 / 帮我决定 / 系统监视
    tools3.js      记账本 / 习惯打卡 / 计算器
    tools4.js      倒数日 / 单位换算 / 密码生成器
    tools5.js      衣橱 / 成就 / 剪贴板
    tools6.js      快捷启动 / 节日日历
    tools7.js      外出探险+每日任务 / 钓鱼（canvas 场景，白天/黄昏/夜晚）
    tools8.js      宠物花园 / 扭蛋机 / 接食物（小游戏）
    bongo-page.js  键鼠映射设置页
    games/*.js     各小游戏，一个游戏一对 .js/.css（riichi/ 为日麻，子目录）
    start.js       最后加载，调用 Hub.start()
  theme-bridge.js 主进程：CML 主题桥（读取 / 监视 theme.json，推送 cml-theme:changed，同步 nativeTheme）
  shared/        宠物窗口与 Hub 共用：cml-theme（把 CML 主题映射到 CSS 变量）、wardrobe（装扮）、anchors（宠物头部坐标）、festivals、mjtiles、bongo-*
assets/pets/     20 张宠物立绘 320x320 PNG（文件名即宠物 id，如 01-fox.png）
build/icon.ico   打包图标
test/            Electron 驱动的端到端脚本 + 截图输出（test/out）+ 隔离的用户数据（test/userdata）
dist/            构建产物（DesktopPet.exe 便携版）
```

## 进程与数据流

- **主进程拥有所有持久状态**：`userData/data.json`（`data` 对象），`save()` 300ms 防抖写盘。
  顶层键：`settings`、`care`（需求值/等级/小鱼干/背包/装扮）、`stats`、`achievements`、`quests`、`trip`、
  `souvenirs`、`fishdex`、`fishDay`、`garden`、`gacha`、`gachaFree`、`gachaPity`、`mod:<模块id>`（Hub 页面私有存储）等。
- 渲染进程 → 主进程：`window.api.*`（preload.js）。同步读取用 `ipcRenderer.sendSync` + `e.returnValue`，
  单向通知用 `send`。主进程 → 渲染进程：`broadcast(channel, payload)` 同时发给宠物窗口和 Hub
  （如 `care`、`play`、`pet:say`、`achievement`）。
- **经济规则只在主进程里实现**：扣币/加币、防刷上限（钓鱼每日 80）、掉落概率都在 main.js / play.js，
  渲染进程只上报事件（如 `api.play.fish({...})`、`api.play.garden(op, a)`），不能直接改余额。
- 游戏胜利发奖：页面调用 `ctx.reward(coins, reason)` → `care:reward` → `reward()`。单次最多 100。
  `reason` 会被当作游戏名记入 `stats.gameKinds`，并增加 wins（名字里带 番茄/签到/习惯/测试 的除外）。

## 常见修改怎么做

### 新增 Hub 页面 / 小游戏
1. 读 `src/hub/MODULES.md`（`Hub.register({ id, title, group, order, icon, mount(el, ctx), unmount })`）。
   `group` 取 `pet` / `tool` / `game`，侧栏里同组按 `order` 排序。
2. 新建 `hub/games/xxx.js` + `.css`（或放进某个 toolsN.js），CSS 全部挂在根类下面，比如 `.xx-root …`。
3. 在 `hub/index.html` 里加上对应的 `<link>` 和 `<script>`，`<script>` 必须放在 `start.js` 之前。
4. 在 `hub/tools.js` 的首页磁贴数组 `tiles` 里加 `['id', '标题', '副标题']`。
5. 窗口级监听一律在 `unmount` 里移除。键盘事件先检查 `ctx.isActive()`；rAF 循环要在 unmount 里 cancel。
6. 宠物立绘：`api.petImage(api.settings.get().pet)` 返回 data URL，可以直接用在 `<img>` 或 canvas 里。

### 新增需要持久化/经济的玩法
- 逻辑写在 `src/play.js` 的 `init()` 内部，并加进最后的 `return {...}`。需要给 UI 展示的状态放进 `playState()`。
- 在 `main.js` 的「每日任务 / 外出探险 / 钓鱼」一节注册 `ipcMain.on('play:xxx', ...)`，
  在 `preload.js` 的 `play: {}` 里暴露。
- 时间相关的玩法（探险、花园）用 `Date.now()` 时间戳计算，这样离线期间也会推进；
  主进程每 20 秒调用一次 `play.tick()`，用于到点提醒。
- 状态变化后调用 `careChanged()`（存盘并广播 care）和 `broadcast('play', playState())`。

### 每日任务 / 成就
- 任务池：`play.js` 顶部的 `QUEST_POOL`。在触发点调用 `questEvent(key, n)`。
  main.js 里 `bump()` 的 wins/pomos/feeds/pets 会自动转发给任务系统。
- 成就：`main.js` 的 `ACHIEVEMENTS` 数组（`test(stats, care)`）。计数用 `bump(key)`（IPC `stats:bump`），
  最大值类统计用 `stats:set`（必须在 main.js 的白名单分支里处理）。改完后别忘了首页磁贴上的「N 个成就」。
- ⚠️ **坑**：`stats()` / `care()` 每次调用都会用 `Object.assign` 重建对象并重新赋给 `data.stats` / `data.care`。
  先取引用、再调用一次 `stats()`、然后往旧引用里写，这次写入就会丢失。
  正确写法是 `const s = stats();` 之后只通过 `s` 读写，或者每次写都直接写 `stats().x = ...` 这一个表达式。

### 商店 / 食物 / 装扮
- 商品和效果：`main.js` 的 `SHOP`。图标 SVG：`hub/tools2.js` 的 `ITEMS`。宠物窗口的喂食列表在 `pet/pet.js` 的 `FOODS`。
- 装扮目录：`shared/wardrobe.js`，主进程和两个渲染窗口共用这一份。

### 新增宠物
- 往 `assets/pets/` 放一张 320x320 的透明 PNG（按文件名排序），再往 `shared/anchors.js` 里补上它的头部坐标（装扮定位要用）。

## 主题系统
- 主题跟随 CML 启动器，在 CML 设置 → 外观 中切换；应用内没有主题页、托盘 / 右键「主题」菜单或 `settings.theme`
  （旧数据里的 `settings.theme` 会在启动时删除）。协议见 CML 仓库 `docs/THEME_BRIDGE.md`。
- 主进程 `src/theme-bridge.js`：按 `CML_THEME_FILE` → `%APPDATA%/CML/theme.json` → 内置默认配色（浅色，主色 `#4fa3d9`）读取；
  `fs.watch` 监视所在目录（CML 先写 `theme.json.tmp` 再重命名，150ms 防抖），变化后向所有窗口发送 `cml-theme:changed`，
  并设置 `nativeTheme.themeSource`、Hub 窗口背景色。解析失败时保持当前配色。preload 暴露 `window.cmlTheme.get() / onChange(cb)`。
- 渲染进程 `src/shared/cml-theme.js`（`window.PetTheme`）：`PetTheme.init(onChange)` 同步取当前主题并订阅变化，
  把 CML 的 bg / panel / surface / line / accent / text / muted / field / onAccent 写成 CSS 变量，深色时给 `<html>` 加 `.theme-dark`。
  Hub（hub.js）和宠物窗口（pet.js，换色时冒一句「换上「…」主题啦~」）各调用一次。键鼠看板（bongo）使用自己的花色，不跟随主题。
- 派生变量：`--accent-2`（标题 / 强调文字，由 accent 与 text 用 color-mix 混合；CML 的 accent2 是浅色辅助色，作为 `--accent-alt` 提供）、
  `--field`（输入框、按钮）、`--on-accent`（强调色上的文字，来自 CML 的 onAccent）、`--shadow`。
- **写新样式时**：
  - 不要写死 `#fff` 背景或棕、橙色，改用 `var(--field)`、`var(--panel)`、`var(--accent)` 等变量；
  - 浅色底纹用 `color-mix(in srgb, var(--accent) 10%, var(--panel))`；
  - 强调色背景上的文字用 `var(--on-accent)`。
- 游戏画面里的实物美术（棋盘、牌面、扭蛋机、钓鱼场景等）保持固定配色，不跟随主题。
  但如果它们上面叠了文字，文字颜色也要固定，不能写成 `var(--text)`，否则在深色主题下会看不清。
- 验证：运行 `npx electron test/themes.js`：它写一个临时的 `CML_THEME_FILE`，依次换成 light / sakura / dark 三套 CML 配色，
  对 Hub 页面和宠物窗口截图到 `test/out/themes/`；可用 `THEMES=light,dark PAGES=x,y` 指定。

## 样式约定
- 主题变量（默认值 = CML 默认配色，在 `hub/hub.css` 的 `:root`）：`--bg --panel --surface --line --accent --accent-2 --accent-alt --text --muted --field --on-accent --radius --shadow`。
- 通用类：`.card`、`.btn`、`.btn.primary`、`.page-title`、`.set-sub`、`.side-title`、`.hidden`（由各模块自己定义显示规则）。
  可复用的动画：`toastIn`、`advPop`（弹窗）、`fsSpin`（旋转光芒）。
- 图形只用内联 SVG / CSS / canvas 绘制，不引用外部图片，也不访问网络（CSP：`default-src 'self'; img-src 'self' data:`）。
- 内容区大约 760x600，需要自适应居中；canvas 按 `devicePixelRatio` 放大绘制，保证高分屏清晰。
- 稀有度配色约定：普通为绿 `#4f8a45`，稀有为蓝 `#3a78b8`，珍贵为金 `#c98a00`，底色 `#ffd66a`。

## 运行 / 测试 / 构建（Windows，Git Bash）
- 开发运行：`npm start`
- 调试日志：设置环境变量 `DESKTOPPET_DEBUG=1`，日志写到 `userData/debug.log`
- 端到端测试：`npx electron test/<脚本>.js`。脚本会 `require('../src/main.js')`，用户数据隔离在 `test/userdata`，
  截图输出到 `test/out/`，并在最后打印 `ERRORS:`（渲染进程的 console error/warning）。
  - 在脚本里调用主进程 IPC：`const e = {}; ipcMain.emit('play:get', e); e.returnValue`
  - 模拟输入用 `wc.sendInputEvent`，在页面里执行代码用 `wc.executeJavaScript`
  - 快进时间的做法：在主进程里 `Date.now = () => realNow() + skew`，同时在页面里注入同样的偏移（参见 `test/play.js`、`test/play3.js`）
  - 现有脚本：`fish.js`（钓鱼，白天/黄昏/夜晚）、`play3.js`（花园/扭蛋/接食物）、`newgames.js`、`shot.js` 等
- 构建：`cmd //c "npm run dist"`（在 Git Bash 里要这样调用，因为 npm script 里用的是 Windows 的 `set` 语法），
  产物是 `dist/DesktopPet.exe`（便携版，约 100MB）。使用 npmmirror 镜像，`npmRebuild: false`。
- 修改后至少跑一遍 `node --check` 检查改过的 JS，再跑相关的 test 脚本并查看截图。
- **CML 内置版**：CML 只附带一份共享的 Electron 运行时，以 `apps/runtime/electron.exe apps/desktoppet/app` 启动本应用
  （CML 仓库的 `apps/build-apps.ps1` 暂存 `src/ assets/`、精简的 package.json 与 `uiohook-napi` + `node-gyp-build`，输出到 `out/app`）。
  此时 `app.isPackaged === false`：main.js 开头显式 `app.setName('DesktopPet')`，并把 userData 固定为 `%APPDATA%/DesktopPet`
  （测试脚本先 `setPath` 的自定义目录会保留），再取单实例锁，因此锁和数据都按应用区分；开机自启写入
  `electron.exe "<app 目录>"`（`process.execPath` + `app.getAppPath()`），从 `node_modules/electron` 开发运行时不注册。
