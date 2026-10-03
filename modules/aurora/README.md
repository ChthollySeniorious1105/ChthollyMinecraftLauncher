# Aurora 联机小游戏

客户端与服务端分离的联机游戏程序，全部通信走 **单条长连接**（游戏数据、文字聊天、语音都在同一连接内）：原生客户端用 TCP，**网页版**在浏览器里通过 WebSocket 连接同一个服务器，两种客户端可以在同一房间一起玩。适合配合内网穿透（frp / Sakura / Tailscale 等）的 TCP 隧道使用。

## 目录

| 目录 | 说明 |
|---|---|
| `server/` | 服务端（Dart 控制台程序，编译为 `aurora_server.exe`） |
| `client/` | 客户端（Flutter：Windows / Android / macOS / iOS / 网页） |
| `shared/` | 共享协议与全部游戏规则引擎（服务端权威运行，杜绝作弊） |
| `assets/` | 原始 500 个玩家形象（已复制到 `client/assets/avatars`） |
| `GAME_DEV_GUIDE.md` | 新增游戏的开发规范 |

## 服务端

```
aurora_server.exe                 # 首次运行交互式输入端口和服务器名称，保存到 aurora_server.json
aurora_server.exe --port 9000     # 指定端口
aurora_server.exe --port 9000 --name "周末麻将局"
aurora_server.exe --web-port 8080     # 网页版端口（默认 7790，0 = 关闭网页版）
```

- 端口自选，默认 7788；启动后会列出本机所有 IP。
- **网页版**：服务器同时在网页版端口（默认 7790，`aurora_server.json` 的 `webPort` 或 `--web-port`）提供 HTTP 服务，玩家用浏览器打开 `http://服务器地址:7790` 即可直接游玩，无需安装客户端。
  - 网页客户端文件放在 exe 同目录的 `web` 文件夹（发布包已包含；自行构建见下方「构建」）。没有 `web` 文件夹时浏览器只会看到提示页。
  - 同一端口的 `/ws` 是 WebSocket 游戏连接，协议与原生客户端完全相同（X25519 + ChaCha20-Poly1305 端到端加密、同样的防滥用限制），网页和原生玩家可在同一房间。
  - 内网穿透时把 TCP 7790 也映射出去。放在 nginx / Caddy 后面用 HTTPS 时，需反代 WebSocket（`/ws` 的 Upgrade 头），并在 `.env` 设 `TRUST_PROXY=true` 以按真实 IP 限流/封禁；HTTPS 页面只能连接 `wss://` 地址。
  - 网页版的限制：没有局域网搜索（浏览器不能发 UDP）；本机回放保存在浏览器存储里（最多 20 局）；语音需要浏览器授权麦克风，且只有 HTTPS 或 localhost 页面才能使用麦克风。
- 也可以双击 `启动服务器.bat`。
- 房主可设置每步思考时间（15 秒～5 分钟或不限），超时由电脑代打一步。
- 聊天与语音有简单的防刷屏限速。
- 任何玩家都可以创建房间（可设密码），房间内无在线成员超过 **3 分钟** 自动销毁。
- 房间号为随机 5 位大写字母+数字（如 `A7K2Q`）。房间可设为 **公开**（大厅可见）或 **私密**（不在大厅显示，只能输入房间号进入），房主可随时切换。
- 房间内房主可随时 **更换游戏**，成员保留；座位数自动随新游戏调整。
- 所有游戏支持 **观战**：进入房间时可选"以观战者身份进入"，或在房间里点"观战"离开座位；观战者看不到任何玩家的私密信息。
- 只有当入座人数满足该游戏的人数要求时，房主才能开始游戏。
- 断线 10 分钟内重连可回到原房间原座位；对局中离开/掉线由电脑托管。
- 内网穿透：把本机 `TCP <端口>` 映射出去即可，客户端填写穿透后的 `地址:端口`（网页版另映射网页版端口）。
- **自定义词库**：首次启动会在 exe 同目录生成 `words` 文件夹（UTF-8 文本，保存后对新开的对局生效，控制台 `words` 命令查看条数）：
  - `words/drawguess.txt`：你画我猜，每行 `词语` 或 `词语|类别`
  - `words/undercover.txt`：谁是卧底，每行 `平民词|卧底词`
  - `words/turtlesoup.txt`：海龟汤，每行 `标题|汤面|汤底`
  - `words/decrypto.txt`：截码战，每行一个关键词
  - `words/justone.txt`：Just One 合作猜词，每行一个词
  - `words/wavelength.txt`：频率猜心，每行 `左概念|右概念`（如 `冷|热`）
  - 房间的「词库」选项可选 内置+自定义 / 仅自定义 / 仅内置。
- **配置文件 `.env`**：首次启动会在 exe 同目录生成带中文注释的模板 `.env.example`，复制为 `.env`（exe 同目录，其次当前目录）修改后重启生效。格式 `KEY=VALUE`，`#` 为注释，值可加引号。
- **大模型 AI 电脑玩家**（可选）：`.env` 中设置 `AI_PROVIDER=anthropic`（`ANTHROPIC_API_KEY`，默认模型 `claude-opus-5`）或 `AI_PROVIDER=openai`（`OPENAI_API_KEY` / `OPENAI_MODEL` / `OPENAI_BASE_URL`，可接任何 OpenAI 兼容服务如 DeepSeek、通义、Kimi、本地 Ollama；部分新模型需 `OPENAI_TOKEN_PARAM=max_completion_tokens`）。
  - 房间开启游戏的「AI 电脑」选项后，电脑玩家由大模型扮演（描述、猜词、聊天类游戏）；失败/超时/被拒答时自动退回普通电脑算法。
  - `AI_VISION` 模型能否看图（你画我猜 AI 猜画）；`AI_MAX_CONCURRENCY` 并发数；`AI_TIMEOUT` 单次超时秒数；`AI_DAILY_LIMIT` 每日请求上限（超出后当天自动停用 AI）。
  - 密钥只保存在 `.env`，不会打印到控制台或发送给玩家；请勿分享 `.env`。
- **战绩与 Elo**：每局结束按名次记录每位玩家（客户端生成的匿名 uid 经服务器盐值哈希，盐值保存在 `aurora_server.json` 的 `salt`，删除会重置所有人的战绩身份）。每个游戏独立 Elo（初始 1500，K=32，只在真人之间结算；与电脑对局只计局数/胜场），至少 3 局上排行榜。数据保存在 `data/stats.json`。房间内另有本房间连续对局积分榜（第 1 名 +3 分）。
- **回放**：每局结束自动保存到 `replays/`（gzip 压缩，`index.jsonl` 为索引），超过 `REPLAY_KEEP`（默认 2000）局删除最旧的。只有已结束的对局可以查看，查看时可切换任意座位视角。
- **房间功能**：电脑难度（简单/普通/困难）、托管、认输、求和、悔棋（仅支持悔棋的棋类，需对手同意，30 秒无响应自动拒绝）、表情/快捷语、房主踢人（被踢者 5 分钟内不能再进该房间）。
- **局域网发现**：服务器监听 UDP 7789，客户端连接页可“搜索局域网服务器”（需防火墙放行 UDP 7789）。
- 控制台命令：`rooms` 列房间、`users` 列在线玩家（含 `#id`）、`kick <#id>` 断开玩家、`ban <#id>` 断开并封禁其 IP（到重启为止）、`say <文本>` 全服公告、`ai` 查看 AI 状态/今日用量/最近错误、`replays` 回放数量与占用空间、`stats` 战绩人数、`quit` 关闭。

## 通讯安全

- **全程加密**：客户端与服务器先做 X25519 密钥交换（每次连接一次性密钥 + 服务器长期身份密钥），之后所有游戏数据、聊天、语音都用 ChaCha20-Poly1305 加密并校验，被篡改、重放或乱序的数据包会直接断开连接。内网穿透服务商或同一局域网的人都看不到内容。
- **防冒充服务器**：服务器首次启动生成 `server_identity.key`（与 exe 同目录，**请妥善保管、不要外传，重装时一起备份**），控制台会显示"服务器指纹"。客户端第一次连接某地址时记住该身份，之后若身份变化会拒绝连接并警告（类似 SSH），确认安全后才可选择"信任新身份"。
- **服务器权威**：所有游戏规则只在服务器执行，客户端只收到自己有权看到的信息（别人的手牌、身份、牌堆等不会发给客户端），无法通过改客户端作弊。
- **防滥用**：单 IP 连接数限制、握手超时、消息/聊天/语音限速、单帧大小上限、房间密码错误 5 次锁定 2 分钟（常量时间比较）、昵称/聊天过滤控制字符与 Unicode 方向控制符、房间数与在线身份数上限、异常不回显内部错误信息。
- 旧版客户端（未加密协议）会被拒绝并提示更新。

## 客户端

首次启动设置昵称（≤18 个英文字符 / ≤9 个中文字符）和 500 种形象之一，然后填写 `服务器IP:端口` 连接。

- 大厅：房间列表、创建房间（选游戏和规则）、大厅聊天。
- 房间：座位（可添加电脑玩家）、准备/开始、观战、房主换游戏/改规则、文字聊天、语音。
- 语音：16 kHz 单声道，μ-law 压缩，经服务端转发；降噪 = 系统级降噪/回声消除/自动增益 + 软件降噪（高通滤波 + 自适应噪声底估计 + 谱减式增益 + 噪声门），降噪强度 4 档可调；支持按键说话、静音、闭麦。
- 主题：36 款界面主题（设置 → 主题与设置），并可调界面缩放。
- 局域网发现：连接页“搜索局域网服务器”，UDP 广播到 7789 端口，2 秒内列出同一网络的服务器，点击填入地址。
- 单机游戏：连接页“单机游戏（与电脑对战）”，无需服务器，在本机运行游戏引擎；可选人数（你 + 电脑）、电脑难度、规则选项，支持托管、认输、求和（电脑总是同意）、悔棋（支持悔棋的棋类），结束后自动保存回放，可“再来一局”。
- 对局中：表情/快捷语（浮动气泡 + 聊天记录）、托管、认输、求和/悔棋请求（其他真人玩家弹窗同意/拒绝）、规则说明。
- 房间：电脑难度（简单/普通/困难）、积分榜（本房间连续对局）、规则说明、复制邀请文本（服务器地址 + 房间号）、房主可点成员踢出房间；游戏有“AI 电脑”选项但服务器未配置大模型时会提示。
- 回放：大厅 → 对局回放（全部 / 我的 / 本机），播放器支持时间轴拖动、播放/暂停、0.5x~4x 倍速、逐步前进/后退、切换任意座位或观众视角、对局记录；联机回放可保存到本机（应用文档目录 `aurora_replays/*.aurora-replay.gz`）。
- 战绩：大厅 → 战绩与排行（我的总局数/胜率/各游戏 Elo，按游戏查看排行榜）。玩家身份为客户端首次启动生成的随机 uid（不显示），服务器只保存其哈希。
- 游戏选择器：长按/右键收藏游戏，顶部显示“收藏”与“最近玩过”。
- 音效：轮到我、开局、胜利/失败、表情提示音（程序合成，无素材），设置里可关闭或调音量。

## 构建

Windows 本机（已在 `D:\Tools` 安装 Flutter 3.47.5 与 Android SDK）：

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1      # 生成 dist\ 下的服务端、Windows 客户端、Android APK
```

macOS / iOS 需在 Mac 上构建（Apple 限制）：

```bash
cd client && flutter build macos --release
cd client && flutter build ios --release --no-codesign   # 生成未签名 Runner.app，打包 Payload/ 成 ipa 后用 AltStore / Sideloadly 签名安装
cd server && dart compile exe bin/aurora_server.dart     # macOS 版服务端
```

网页版（任意系统）：

```bash
cd client && flutter build web --release --no-web-resources-cdn
# 把 client/build/web 复制为 aurora_server 同目录的 web 文件夹
```

`--no-web-resources-cdn` 让 CanvasKit 从本服务器加载而不是 gstatic.com（很多网络访问不了）；中文/emoji 字体按需从 `fonts.gstatic.cn` 加载（`web/flutter_bootstrap.js` 可改）。`build-servers.ps1` 打包 Aurora 服务端时会自动构建并附带 `web`。

或推送到 GitHub 后运行 `.github/workflows/build.yml`（macOS runner 自动产出 macOS zip、未签名 ipa、各平台服务端）。

## 测试

```
cd server && dart test                       # 服务端：房间/聊天/语音转发/重连/空房销毁/超时代打/网页版（静态文件 + WebSocket）
cd client && flutter test                    # 客户端：所有牌桌在手机竖屏/横屏/桌面尺寸渲染、降噪、真实客户端↔服务器端到端对局
SHOTS=1 flutter test test/screenshot_test.dart   # 把每个游戏和界面截图到 client/build/shots/ 便于人工检查
cd shared && dart test                       # 各游戏规则单测 + 电脑对打模拟
cd shared && dart run tool/simulate.dart all 20
```

## 素材版权

- 麻将牌面：[FluffyStuff/riichi-mahjong-tiles](https://github.com/FluffyStuff/riichi-mahjong-tiles)，CC0 公有领域（`client/assets/mahjong/LICENSE.md`）。
- 扑克、UNO、骰子等牌面均为程序绘制，不使用任何受版权保护的美术资源。
- 界面风格参考雀魂，但不包含其任何素材。
