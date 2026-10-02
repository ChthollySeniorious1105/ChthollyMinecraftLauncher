# ChthollyMinecraftLauncher (CML) — 架构

Windows 桌面 Minecraft 启动器（参考 Plain Craft Launcher 的功能范围），外加 CMLS 联机服务端。

## 目录

| 目录 | 说明 |
|---|---|
| `core/` | 纯 Dart 核心库 `cml_core`，无 Flutter 依赖，可单测、可被 CLI/服务端复用 |
| `launcher/` | Flutter Windows 客户端（UI），只做界面与状态，业务全部调用 `cml_core` |
| `server/` | CMLS：安全联机中继服务端（Dart 控制台程序 → `cmls.exe`） |
| `build.ps1` | 一键测试 + 构建 `dist\` |

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
