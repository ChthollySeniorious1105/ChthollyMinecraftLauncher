# ChthollyMinecraftLauncher (CML) — 架构

Windows 桌面 Minecraft 启动器（参考 Plain Craft Launcher 的功能范围），外加 CMLS 联机服务端。

## 目录

| 目录 | 说明 |
|---|---|
| `core/` | 纯 Dart 核心库 `cml_core`（游戏安装/启动、账号、下载、格式转换、联机隧道、分包管理 `addons/`、BedrockTool / 网易存档封装 `bedrock/`） |
| `launcher/` | Flutter Windows 客户端（UI）。内嵌 Aurora / Pulse 两个 Flutter 模块；`windows/` 同时编译 `pulse_native.dll` |
| `server/` | CMLS 联机中继服务端（Java TCP 中继 + 基岩版 UDP 中继） |
| `modules/aurora/` | Aurora 联机小游戏（`shared` 规则引擎 + `server` 服务端 + `client` 作为 Flutter 包 `aurora_client` 嵌入 CML） |
| `modules/pulse/` | Pulse 文字 / 语音聊天（`shared` 协议 + `server` 服务端 + `client` 作为 Flutter 包 `pulse_client` 嵌入 CML，`client/native` 为 C++ 音频引擎） |
| `tools/bedrocktool/` | BedrockTool（Go，GPL-3）源码，CML 内以原生页面「基岩版工具」驱动其 CLI |
| `tools/netease/` | 网易基岩版存档解密工具（第三方二进制，CML 页面驱动） |
| `tools/lumikeymapper/` | LumiKeyMapper 键鼠映射（WPF / .NET 10，独立 exe） |
| `apps/` | DesktopPet / LiteEditor / LiteReader（Electron），共用一份 `apps/runtime` Electron 运行时 |
| `docs/THEME_BRIDGE.md` | CML → 外部应用的主题桥协议 |
| `build.ps1` | 一键测试 + 构建 `dist\`（主包、CMLS、分包） |

## core 模块划分（`core/lib/src/<模块>/`）

| 模块 | 内容 |
|---|---|
| `net/` | HTTP 客户端封装、下载器（多线程、断点续传、SHA1 校验、重试、镜像源回退）、`DownloadSource`（官方 / BMCLAPI / MCIM） |
| `game/` | 版本清单、版本 JSON 解析（继承 `inheritsFrom`、rules、natives、arguments 新旧格式）、安装（client/libraries/assets）、Mod 加载器安装（Fabric / Quilt / Forge / NeoForge）、启动参数构建与进程启动、实例（版本隔离）管理 |
| `auth/` | 微软账号 OAuth 设备码流程 → Xbox Live → XSTS → Minecraft 令牌 → 档案；刷新令牌；皮肤上传、披风切换；SSL 证书校验开关 |
| `java/` | Java 自动扫描（注册表、常见目录、PATH、`.minecraft/runtime`）、版本识别、按 MC 版本自动选择、Java 下载（Mojang runtime / Adoptium / BMCLAPI 镜像） |
| `content/` | Modrinth + CurseForge(MCIM 镜像) 搜索与下载：Mod / 整合包 / 光影 / 资源包 / 数据包；整合包安装（`.mrpack`、CurseForge zip） |
| `bedrock/` | 商店应用启动（`shell:AppsFolder\<AUMID>`）：基岩版、Legends、Dungeons、Dungeons II；基岩版存档（`com.mojang/minecraftWorlds` 及 GDK 版 `%APPDATA%\Minecraft Bedrock\Users\*\games\com.mojang`）管理 |
| `saves/` | Java 存档管理（level.dat NBT 读写、备份/导入导出）、版本转换（调用 Chunker CLI） |
| `nbt/` | NBT 读写（Java 大端 / 基岩小端 / 网络格式），gzip/zlib |
| `structure/` | 建筑文件互转：`.schematic`（MCEdit 旧格式）、`.schem`（Sponge v2/v3）、`.litematic`、`.mcstructure`、`.bdx`（Bedrock 建筑导出格式），统一中间表示 `Structure`，含 Java ⇄ 基岩方块映射表 |
| `resourcepack/` | 资源包版本无损转换：`pack.mcmeta` pack_format / 新式 `min_format`/`max_format` 改写、1.13 扁平化纹理重命名、1.19.3 atlas 等文件结构迁移（只改名/改元数据，不重编码图片） |
| `skin/` | 皮肤 PNG 读写、64×32 → 64×64 升级、经典/纤细模型 |
| `tools/` | GitHub Release 组件管理器（检查最新版、下载、解压、版本记录）：mihomo（Clash Verge 内核）、Chunker CLI |
| `proxy/` | mihomo 进程管理：订阅导入、配置生成、启停、系统代理、外部控制 API（节点切换、延迟测试、流量） |
| `tunnel/` | CMLS 客户端：加密通道 + 局域网游戏转发 |
| `memory/` | 内存优化：`EmptyWorkingSet` / `SetProcessWorkingSetSize` 裁剪工作集，系统待机列表清理（需管理员）；空闲内存查询 → 自动分配内存 |
| `update/` | 启动器自更新（GitHub Release，下载 → 校验 → 替换脚本重启） |
| `config/` | 全局设置与实例设置（JSON），数据目录 `%APPDATA%\CML` |

## 联机（CMLS）

- 加密通道沿用 Aurora / Pulse 的构造：X25519 临时密钥 + 服务器静态身份密钥 → HKDF-SHA256 → ChaCha20-Poly1305，每方向计数器防重放；客户端按地址钉扎服务器指纹（TOFU）。协议标签改为 `cml-v1`。
- 房间模型：房主在 MC 里"对局域网开放"后，CML 读取本地端口，在 CMLS 上创建房间（房间号 + 可选密码）；其他玩家加入后，CML 在本机监听一个端口并模拟局域网广播（UDP `224.0.2.60:4445` 的 `[MOTD]..[/MOTD][AD]port[/AD]`），MC 多人游戏列表里直接出现该房间。
- 数据流：客户端 TCP ⇄ CML 本地端口 ⇄ 加密通道（多路复用 stream id）⇄ CMLS ⇄ 加密通道 ⇄ 房主 CML ⇄ 房主 MC LAN 端口。服务器只转发密文外的帧，看不到加密内容以外的游戏数据（服务器本身是端点，转发的是 MC 原始流量；与服务器之间的链路全程加密）。
- 防滥用：单 IP 连接数、握手超时、帧大小上限、房间密码错误锁定、房间数上限。

### 基岩版 UDP 联机

- 基岩版走 RakNet/UDP（默认 19132 IPv4 / 19133 IPv6）。CML 不另开加密 UDP 通道：每个 UDP 报文原样装进现有加密 TCP 通道的新帧类型 `FrameKind.datagram = 3`（`u32 flowId | 一个完整报文`），一帧一个报文，保留消息边界；报文上限 2048 字节（RakNet MTU ≤ 1500）。协议细节写在 `core/lib/src/tunnel/protocol.dart` 头注释，RakNet 离线报文与 pong 字符串解析在 `core/lib/src/tunnel/bedrock.dart`。
- 控制消息（向后兼容，Java 房间与 `cml-v1` 握手不变）：`auth` 带 `caps:['bedrock']`；`host` 带 `edition:'bedrock'`、`bedrock:{motd,protocol,version,players,max,…}`、`publicUdp`；`rooms`/`joined` 带 `edition`；`binfo` 更新 pong 信息；`uopen {sid}` / `uclose {sid}` 开关 UDP 流（每个本地游戏端点 ip:port 一个流），空闲 60 s 自动关闭。旧版 CML 不能加入基岩版房间（服务器拒绝并提示更新）；旧版 CMLS 不回显 `edition` 时 CML 放弃创建并提示升级服务器。
- 房主：`TunnelClient.detectLocalBedrock()` 向 127.0.0.1:19132/19133 发 Unconnected Ping 解析 pong（MOTD、版本、协议号、人数）；创建房间后，每个访客流在房主机上开一个独立的临时端口 UDP 套接字，与 `127.0.0.1:<udpPort>`（基岩版"对局域网玩家可见"的世界或 BDS）双向转发，只接受来自该游戏端口的回包；每 10 s 重新 ping 一次，信息变化时通过 `binfo` 推给访客。
- 访客：CML 绑定 `0.0.0.0:19132`（不设 SO_REUSEADDR，避免和本机基岩版服务器静默共用端口），自己用房间信息（MOTD = 房间名，协议号/版本 = 房主上报）回答 Unconnected Ping，房间就会出现在"好友 → 局域网游戏"中；默认只接受本机地址的报文。19132 被占用时回退到随机端口，此时局域网发现不可用，界面提示"添加服务器 127.0.0.1:<端口>"。
- CMLS：按房间分配流 id 并在访客流和房主之间转发 datagram 帧；每访客 8 个流、每房间 64 个流；每流每方向令牌桶（2000 包/s、2 MiB/s）+ 每连接总令牌桶；接收端 TCP 发送队列超过 256 KiB 时直接丢弃报文（绝不无限排队，TCP 数据与控制消息照常排队）。
- 可选公网入口 `cmls.exe --public-udp <端口>`（别名 `--udp-port`，默认关闭；`--public-udp-room <房间号>` 固定公开某个房间，否则由房主勾选"公网直连"认领，仅限无密码房间、同一时间一个房间；`--public-udp-max` 总流数，默认 32；控制台命令 `public <房间号|off>`）：CMLS 在该 UDP 端口上像普通基岩版服务器一样回答 ping（MOTD = 房间名，副标题 = 服务器名），并把任何互联网基岩版客户端的原始 RakNet 报文经隧道转给房主，没有 CML 的玩家可以直接"添加服务器 <CMLS 地址>:<端口>"。
  - **安全取舍**：这等同于把房主的游戏公开到互联网——房间密码对公网入口无效，只能依赖游戏自身的 Xbox 登录 / 白名单 / 权限；服务器能看到 RakNet 明文（与普通服务器相同，房主与 CMLS 之间仍然加密）。防护：新流必须以 Open Connection Request 1 开始（垃圾包不分配状态）、每源 IP 最多 4 个流且新建流限速、ping 回复按源 IP 和全局限速（pong 比 ping 大，防反射放大）、封禁 IP 同样作用于 UDP。需要额外放行 / 映射该 UDP 端口。

## 打包与分包

`build.ps1` 输出：

| 文件 | 内容 |
|---|---|
| `CML-<ver>-windows-x64.zip` | 主程序：cml.exe、Flutter 运行时、pulse_native.dll（+Opus / ONNX Runtime / DirectML）、`tools\`、`apps\` |
| `CMLS-<ver>-windows-x64.zip` | 联机中继服务端 |
| `CML-addon-pulse-ai-models-<ver>.zip` | 分包：Pulse AI 变声基础模型（HuBERT / RMVPE / RVC，约 810 MB） |
| `CML-addon-pulse-ai-voices-<ver>.zip` | 分包（可选）：额外 RVC 音色 |
| `cml-addons.json` | 分包清单 `{addons:[{id,version,asset,size,sha256}]}` |

分包由 `core/lib/src/addons/addons.dart` 的 `AddonManager` 从最新 Release 读取清单、下载、SHA-256 校验后解压到 `%APPDATA%\CML\addons\<id>`（CML 自更新不会删除）。
CML 启动时若已装 `pulse-ai-models`，设置进程环境变量 `PULSE_MODELS_DIR`，`pulse_native.dll` 从这里加载模型；音色目录通过 `voicesDirOverride` 指向 `addons\pulse-ai-voices\voices`。

## 主题

CML 是唯一的主题来源（`launcher/lib/theme.dart`，6 组 60+ 款）。每次切换写入 `%APPDATA%\CML\theme.json`（`ThemeBridge`）：

- Aurora / Pulse：`launcher/lib/module_themes.dart` 把当前调色板映射成 `AuroraTheme` / `PulseTheme`，通过各模块的 `hostTheme` 注入，模块自身的主题选择器在嵌入时隐藏。
- DesktopPet / LiteEditor / LiteReader / LumiKeyMapper：各自内置主题已移除，监视 `theme.json`（或环境变量 `CML_THEME_FILE`）实时换色，格式见 `docs/THEME_BRIDGE.md`。

## 关键外部源

| 用途 | 官方 | 镜像 |
|---|---|---|
| 版本清单/客户端/库/资源 | piston-meta / libraries.minecraft.net / resources.download.minecraft.net | BMCLAPI `bmclapi2.bangbang93.com` |
| Fabric / Quilt / Forge / NeoForge | meta.fabricmc.net 等 | BMCLAPI |
| Mod/整合包/光影/资源包/数据包 | api.modrinth.com、api.curseforge.com | MCIM `mod.mcimirror.top` |
| Java | Mojang runtime、Adoptium | BMCLAPI / 清华 Adoptium 镜像 |
| mihomo / Chunker / CML 自更新 | GitHub Releases | 可配置 GitHub 加速前缀 |

## 约定

- core 内所有公开 API 不抛裸异常到 UI：用 `CmlException(code, message)`，message 为中文。
- 长任务以 `Task`（进度 0..1、速度、取消）形式暴露，UI 统一显示在任务中心。
- 写入用户存档/资源前先备份到 `%APPDATA%\CML\backups`。
- 不支持离线账号。

---

# 随游戏版本更新的维护指南

每次 Minecraft 发版（Java 正式版 / 快照、基岩版正式版 / 热修复、网易版）后，按下表逐项检查。**大部分内容在运行时从网络获取，不用改代码**。需要改代码或重新生成数据的地方都列出了具体文件。改完后统一走第 9 节的发布流程。

## 0. 总览：哪些东西会随版本变

| 组件 | 随哪个版本变 | 是否需要改代码 | 位置 |
|---|---|---|---|
| Java 版本列表、客户端、库、资源 | Java 发版 | 否（运行时读 piston-meta / BMCLAPI） | `core/lib/src/game/` |
| Mod 加载器（Fabric / Quilt / Forge / NeoForge / OptiFine） | 加载器发版 | 一般不用；安装器格式变化时要改 | `core/lib/src/game/loaders.dart`、`optifine.dart` |
| Java 运行时要求 | 新 Java 版要求新 JDK 时 | **是** | `core/lib/src/game/version.dart` `requiredJava`、`core/lib/src/java/java.dart` `majors` |
| 存档 DataVersion → 版本名 | Java 发版 | **是** | `core/lib/src/saves/worlds.dart` `javaVersionForDataVersion` |
| Java 资源包 pack_format / 迁移规则 | Java 发版 | **是**（重新生成） | `core/tool/gen_pack_rules.py` → `resourcepack/data/pack_rules_data.dart` |
| Java ⇄ 基岩 贴图映射 | 任一版本新增贴图 | **是**（重新生成） | `core/tool/gen_texture_map.py` → `resourcepack/data/texture_map_data.dart` |
| Java ⇄ 基岩 方块映射 | 任一版本新增方块 | **是**（重新生成） | `core/tool/gen_block_map.py` → `structure/data/block_map_data.dart` |
| 建筑文件（.mcstructure / .litematic / .schem）版本号 | 方块状态版本变化 | **是** | `core/lib/src/structure/formats.dart`（block version `18168865`、默认 DataVersion `3955`） |
| 基岩版资源包 manifest | 基岩版发版 | 视情况 | `core/lib/src/resourcepack/bedrock_converter.dart`（`min_engine_version`） |
| Chunker 存档转换 | Chunker 发版 | 否（从 GitHub 自动更新，格式列表运行时解析） | `core/lib/src/tools/chunker.dart` |
| 商店游戏（基岩版 / 预览版 / Legends / Dungeons） | 包名或 AUMID 变化时 | 视情况 | `core/lib/src/bedrock/store_games.dart` |
| 基岩版存档路径（UWP / GDK） | 基岩版改存储位置时 | 视情况 | `core/lib/src/bedrock/store_games.dart`、`saves/worlds.dart` |
| **BedrockTool 网络协议** | **每次基岩版协议号变化** | **是（工作量最大）** | `tools/bedrocktool/`，详见 `tools/bedrocktool/PROTOCOL_UPDATE.md` |
| BedrockTool 支持版本显示 | 同上 | **是** | `core/lib/src/bedrock/bedrocktool.dart` `BedrockToolInfo` |
| 基岩版 UDP 联机（RakNet） | RakNet 协议版本 / pong 格式变化时 | 很少 | `core/lib/src/tunnel/bedrock.dart` |
| Java 联机（局域网广播） | 广播格式变化时 | 很少 | `core/lib/src/tunnel/protocol.dart` `LanBroadcast` |
| 网易存档解密 | 网易改加密方式时 | 换工具 exe | `tools/netease/`、`core/lib/src/bedrock/netease_saves.dart` |
| Aurora / Pulse / 内置应用 | 与游戏版本无关 | 否 | 只在模块自身协议变化时修改各自的 `kProtocolVersion` |

## 1. Java 版发版（正式版）

1. **启动 / 安装**：不用改。用 `core/tool/smoke.dart` 装一次新版本并启动，确认 `arguments`、`natives`、`rules` 解析正常。如果 Mojang 在版本 JSON 里加了新字段，修改 `core/lib/src/game/version.dart`。
2. **Java 版本要求**：版本 JSON 带 `javaVersion.majorVersion` 时自动生效。只有旧格式 JSON 没有这个字段时，才会用 `requiredJava` 里按日期回退的表；需要时新增一行 `if (t.isAfter(DateTime.utc(YYYY, M, D))) return <JDK>;`。出现新的 JDK 大版本时，把它加入 `JavaDownloader.majors`（`core/lib/src/java/java.dart`），并确认 Mojang runtime 组件名以及 Adoptium / BMCLAPI 镜像都已提供。
3. **DataVersion 表**：在 `javaVersionForDataVersion` 的 `table` 里加入 `新DataVersion: '新版本号'`。DataVersion 取自客户端 jar 里 `version.json` 的 `world_version`。
4. **资源包规则**：
   - 把新版本号追加到 `core/tool/gen_pack_rules.py` 的 `ORDER`，把 ORDER 中所有版本的 `<version>.jar` 放到同一目录；
   - 运行 `python core/tool/gen_pack_rules.py <jar目录>`，生成 `pack_rules_data.dart`（含新的 `pack_format` 以及改名 / 切分 / 合并规则）；
   - 如果新版本改用 `min_format` / `max_format` 等新的 `pack.mcmeta` 字段，同步修改 `core/lib/src/resourcepack/resourcepack.dart` 里写 mcmeta 的逻辑；
   - 运行 `dart test test/resourcepack_test.dart`。
5. **Java ⇄ 基岩映射**（有新方块 / 贴图时）：
   - 贴图：`python core/tool/gen_texture_map.py <新 client.jar> <基岩版 vanilla resource_pack 目录>`；
   - 方块：用 GeyserMC mappings（或 mappings-generator 的运行结果）执行 `python core/tool/gen_block_map.py <blocks.json>`；
   - 运行 `dart test`（`features_test.dart` 覆盖结构转换）。
6. **结构文件**：方块状态版本变化时，更新 `formats.dart` 里 `.mcstructure` 写出的 `version`（当前为 `18168865`）和默认 DataVersion。
7. **Mod 加载器**：Fabric / Quilt / NeoForge / Forge 的版本列表在运行时获取。只有 Forge / NeoForge 安装器 `install_profile.json` 的 processors 格式变化时才需要修改 `loaders.dart`。OptiFine 列表来自 BMCLAPI，不用改。
8. **快照**：快照不生成资源包规则，只验证能安装、能启动。

## 2. 基岩版发版

### 2.1 协议号变化（BedrockTool 必须更新）

完整流程见 **`tools/bedrocktool/PROTOCOL_UPDATE.md`**（以它为准；历史记录在同目录的 `V26.44_ADAPTATION.md`、`V26.52_ADAPTATION.md`、`BEDROCKTOOL_VERSION_UPGRADE_GUIDE.md`）。摘要：

1. 根据 Mojang `bedrock-protocol-docs` 变更记录、gophertunnel 上游发布和官方更新日志，确定新版本号和协议号，填好版本矩阵。
2. 判断是热修复（协议号不变，只改 `CurrentVersion`）还是协议升级（包结构有变）。
3. 协议层：修改 `tools/bedrocktool/gophertunnel/minecraft/protocol/info.go` 里的 `CurrentProtocol` / `CurrentVersion`；逐个核对 `protocol/packet/*.go` 的字段顺序、VarInt / LE 编码、Optional 层数和数组长度编码。
4. 内容层：`tools/bedrocktool/dragonfly` 的方块 / 物品注册表和方块状态、维度高度，以及资源包 / 行为包的 `format_version`。
5. 连接层：go-nethernet / go-raknet / Realms 信令（JSON-RPC、ICE、DCEP 时序）。
6. 测试门禁：`go test ./cmd/bedrocktool ./handlers/... ./gophertunnel/minecraft/protocol/... ./dragonfly/...`。
7. 构建：`powershell -File tools/bedrocktool/build.ps1 -Version v<新版本>-cml`，输出 `tools/bedrocktool/out/bedrocktool.exe`。
8. **同步 CML 里显示的版本**：修改 `core/lib/src/bedrock/bedrocktool.dart` 里 `BedrockToolInfo` 的 `supportedVersion` / `gameVersion` / `protocol`。`core/test/bedrocktool_test.dart` 会和 `info.go` 对比，不一致时测试失败。
9. 如果子命令或参数有变，更新 `bedrocktool.dart` 里的参数表（测试会和真实 exe 的 `-h` 输出对比），并在 `launcher/lib/pages/bedrock_tools_page.dart` 加上对应的中文表单项，在 `strings_en_bedrock.dart` 加上英文翻译。

### 2.2 基岩版联机（CMLS / CML 隧道）

- 中继转发的是原始 RakNet 报文，**和游戏协议号无关**，一般不用改。
- 访客端自己回应局域网发现 ping 时，用的是房主上报的协议号和版本（房主每 10 秒重新 ping 一次本机游戏），所以新版本会自动生效。
- 只有以下情况才需要修改 `core/lib/src/tunnel/bedrock.dart`：
  - RakNet 离线消息 magic 或 Unconnected Pong 字段格式（`MCPE;motd;protocol;version;…`）变化；
  - 默认端口变化；
  - Open Connection Request 1 的报文 id 变化（CMLS 公网入口靠它识别新连接）。
- 修改后运行 `cd core && dart test test/tunnel_bedrock_test.dart` 和 `cd server && dart test test/bedrock_test.dart`。

### 2.3 商店 / 存档

- 微软调整 GDK / UWP 包时，核对 `store_games.dart` 里的包族名、AppId 和商店 ID。实际的 AUMID 会在运行时通过 `Get-StartApps` 探测。
- 如果基岩版存档路径再次迁移（目前是 `com.mojang/minecraftWorlds` 和 GDK 的 `%APPDATA%\Minecraft Bedrock\Users\*\games\com.mojang`），更新 `store_games.dart` 和 `saves/worlds.dart` 的搜索目录。
- `bedrock_converter.dart` 生成的 manifest 里的 `min_engine_version`，只有用到要求更高引擎版本的特性时才需要提高。

## 3. 网易版（中国版）

- 网易存档解密由第三方工具 `tools/netease/NeMcDecrypter.exe` 完成（交互式控制台，GBK 编码）。网易更改加密方式后，换成新版工具 exe。如果菜单编号或提示语有变，修改 `core/lib/src/bedrock/netease_saves.dart` 里的菜单常量和输出解析，再运行 `dart test test/bedrocktool_test.dart`（其中包含对假存档的真实调用）。
- 网易存档目录的候选列表也在 `netease_saves.dart` 里，网易调整安装位置时补充。

## 4. 外部工具与组件（自动更新，不用改代码）

| 组件 | 来源 | 机制 |
|---|---|---|
| mihomo（代理内核） | GitHub Releases | `GithubComponent`，启动时检查（设置 → 自动更新工具） |
| Chunker CLI | GitHub `HiveGamesOSS/Chunker` | 同上；可转换的格式列表运行时从 Chunker 解析 |
| Clash Verge Rev | GitHub | 同上 |
| CML 自身 | GitHub `ChthollySeniorious1105/ChthollyMinecraftLauncher` | `SelfUpdater`，资产名 `CML-<ver>-windows-x64.zip` |
| AI 模型分包 | 同一 Release 里的 `cml-addons.json` | `AddonManager`，版本不一致时在「分包管理」里提示更新 |

如果 GitHub 资产的命名规则有变（例如 Chunker 改了 jar 的文件名），修改对应组件的 `pickAsset`。

## 5. 内置模块（与游戏版本无关，但发布时要注意）

- **Aurora / Pulse**：协议版本分别是 `modules/aurora/shared/lib/src/protocol.dart` 和 `modules/pulse/shared/lib/src/protocol.dart` 里的 `kProtocolVersion`。修改客户端 ⇄ 服务端协议时把它加一，并同时发布对应的服务端（`modules/*/server`）。
- **Pulse AI 模型**：模型清单和 SHA256 记录在 `modules/pulse/client/native/models/MODELS.md`。替换模型时更新这个文件，并重新打包分包（`build.ps1 -PulseModels <目录>`）。`native.dart` 里的 `abiVersion` 必须和 `pulse_native.dll` 一致。
- **Electron 应用**：三个应用共用 `apps/runtime`，Electron 大版本必须一致（见 `apps/*/package.json`）。升级 Electron 后运行 `apps/build-apps.ps1` 和各应用的冒烟测试。
- **主题桥**：`docs/THEME_BRIDGE.md` 的字段只增不删。新增字段时同步修改 `launcher/lib/theme.dart` 的 `CmlPalette.toBridgeJson` 和各应用的读取代码。

## 6. 发版前测试清单

```powershell
cd core;   dart test                      # 安装/启动解析、资源包、结构、隧道（含基岩版 UDP）、BedrockTool 封装
cd server; dart test                      # CMLS：Java TCP 中继、基岩版 UDP 中继、公网 UDP 入口
cd launcher; flutter test test\i18n_test.dart   # 所有界面文字都有英文
cd tools\bedrocktool; powershell -File build.ps1  # go test + 构建 + help 冒烟
cd tools\lumikeymapper; powershell -File build.ps1
powershell -File apps\build-apps.ps1
powershell -File build.ps1 -Version <新版本>     # 全量：主包 + CMLS + 分包 + SHA256SUMS
```

手动验收：
- 安装并启动新的 Java 版本；
- 把资源包转换到新版本；
- 用基岩版「下载服务器世界」连接一个新版本的服务器；
- 基岩版联机房间出现在「好友 → 局域网游戏」里，并且能进入；
- Pulse 语音，以及装好分包后的 AI 变声；
- 切换主题后，内置应用跟着变。

## 7. 版本更新记录

每次适配后在下表末尾追加一行：

| 日期 | Java | 基岩版（协议） | BedrockTool 构建 | 数据表重新生成 | 备注 |
|---|---|---|---|---|---|
| 2026-10-02 | 26.2（pack rules） | 26.52（2193） | `v26.52-cml` | pack_rules / texture_map / block_map 未变 | 整合 Aurora、Pulse、BedrockTool、内置应用；新增基岩版 UDP 联机 |

## 8. 常见问题定位

| 现象 | 优先检查 |
|---|---|
| 新 Java 版本一启动就崩溃，或提示 Java 版本不对 | `requiredJava` / `javaVersion` 字段、`JavaDownloader.majors` |
| 资源包转换后贴图丢失 | 是否重新生成了 `pack_rules_data.dart`，`ORDER` 里是否有新版本 |
| 结构文件导入基岩版后方块变成空气 | `block_map_data.dart` 没有新方块；`.mcstructure` 的 block version |
| BedrockTool 连接新服务器时报协议不匹配 | `info.go` 的协议号；见 `PROTOCOL_UPDATE.md` 第 8 节故障表 |
| BedrockTool 页面显示的版本不对 | `BedrockToolInfo` 没有同步（`bedrocktool_test` 会失败） |
| 基岩版联机房间没有出现在局域网列表里 | 访客机的 19132 端口被占用（界面会提示手动添加 127.0.0.1:端口）；房主游戏是否开启了「对局域网玩家可见」；Windows 基岩版的回环豁免 |
| AI 变声提示缺少模型 | 没有安装 `pulse-ai-models` 分包，或 `PULSE_MODELS_DIR` 还没生效（需要重启 CML） |

## 9. 发布流程

1. 按上面各节修改，并通过第 6 节的测试。
2. 运行 `powershell -File build.ps1 -Version <x.y.z>`（打包 Pulse 模型时加 `-PulseModels`，音色包加 `-PulseVoices`）。
3. 在 GitHub 创建 Release `v<x.y.z>`，上传 `dist\` 下的这些文件：`CML-<ver>-windows-x64.zip`、`CMLS-<ver>-windows-x64.zip`、`CML-addon-*.zip`、`cml-addons.json`、`SHA256SUMS.txt`。
4. 用户端：CML 自更新只替换主程序；分包保存在 `%APPDATA%\CML\addons`，用户在「内置应用 → 管理分包」里按版本提示更新。
5. 回滚：重新发布上一个版本的 Release 文件（BedrockTool 的回滚见 `PROTOCOL_UPDATE.md` 9.3 节）。
