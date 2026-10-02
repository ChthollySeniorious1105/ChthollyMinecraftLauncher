# BedrockTool 协议更新标准流程（CML 版，权威文档）

> 本文是 **每次 Minecraft 基岩版发布新版本时** 更新 `tools/bedrocktool` 的可复用操作手册。
> 历史记录（保留，仅供参考）：
> - [BEDROCKTOOL_VERSION_UPGRADE_GUIDE.md](BEDROCKTOOL_VERSION_UPGRADE_GUIDE.md)：1.21.124 / 860 → 1.26.44 / 2168 的迁移过程，以及 Realms/NetherNet 信令修复的经验
> - [V26.44_ADAPTATION.md](V26.44_ADAPTATION.md)：26.44（2168）的适配细节
> - [V26.52_ADAPTATION.md](V26.52_ADAPTATION.md)：26.50/26.52（2193）的适配细节与 JSON-RPC 信令修复
>
> 当前状态：**Minecraft Bedrock 26.52 / 协议 2193 / 协议代码版本 `1.26.52` / 方块版本 `1.21.60.33`（18168865）/ 行为包 `format_version` `1.26.50`**。
> 以下路径都相对于 `tools/bedrocktool/`，除非写明 `core/` 或仓库根目录。

---

## 0. 速查：一次协议升级要改的地方

| # | 文件 / 位置 | 改什么 | 必改? |
|---|---|---|---|
| 1 | `gophertunnel/minecraft/protocol/info.go` | `CurrentProtocol`、`CurrentVersion` | 每次 |
| 2 | `gophertunnel/minecraft/protocol/packet/*.go` | 数据包字段布局（`Marshal(io protocol.IO)`） | 协议号变化时 |
| 3 | `gophertunnel/minecraft/protocol/packet/id.go`、`pool.go` | 新增/删除/改号的数据包 ID 与注册 | 有新包时 |
| 4 | `gophertunnel/minecraft/protocol/*.go`（`item_stack.go`、`player.go`、`skin.go`、`camera.go`、`inventory.go`、`entity_metadata.go`、`command.go`、`recipe.go`…） | 共享结构体、枚举、Optional | 视变更 |
| 5 | `gophertunnel/minecraft/protocol/login/data.go`、`request.go` | `ClientData` 新字段、校验范围（如 `DeviceOS`） | 视变更 |
| 6 | `gophertunnel/minecraft/conn.go` | 登录阶段的版本门槛（第 ~853 行“wire format changed”分支）、`exemptedPacks` 内置资源包版本、`ResourcePackStack.BaseGameVersion` | 大版本时 |
| 7 | `gophertunnel/minecraft/protocol/packet/network_settings.go`、`request_network_settings.go` | 压缩/节流字段 | 视变更 |
| 8 | `dragonfly/server/world/block_states.nbt`、`dragonfly/server/world/vanilla_items.nbt` | 方块状态 / 原版物品注册表 | 内容大版本 |
| 9 | `dragonfly/server/item/creative/creative_items.nbt`、`dragonfly/server/item/recipe/{crafting_data,smithing_data,smithing_trim_data,potion_data}.nbt`、`item_tags.json` | 创造栏、配方、物品标签 | 内容大版本 |
| 10 | `dragonfly/server/world/chunk/encode.go` | `CurrentBlockVersion`（方块版本整数） | 内容大版本 |
| 11 | `dragonfly/server/block/*.go`、`dragonfly/server/block/connection_properties.go` | 新方块 / 状态属性改名（窗格、栏杆、楼梯等连接状态） | 视变更 |
| 12 | `dragonfly/server/world/dimension.go` | 维度高度范围 | 极少 |
| 13 | `dragonfly/server/world/mcdb/leveldat/{data.go,version.go}` | level.dat 中版本字段（自动跟随 `protocol.CurrentVersion`，检查新增字段） | 视变更 |
| 14 | `utils/behaviourpack/bp.go` | `behaviourPackFormatVersion` | 内容大版本 |
| 15 | `utils/proxy/resourcepacks/resourcepacks.go` | `exemptedPacks`（内置原版资源包 UUID_版本） | 原版包版本变化时 |
| 16 | `utils/auth/account.go` | MCToken `ver` 与 `CurrentVersion` 比较（自动跟随，无需改，但需确认登录刷新正常） | 检查 |
| 17 | `utils/franchise/signaling/jsonrpc.go`、`utils/connectinfo/connect_info.go`、`go-nethernet/*` | Realms / 精选服务器 NetherNet 信令 | 服务端改动时 |
| 18 | `go-raknet/*` | RakNet 协议版本 / MTU | 极少 |
| 19 | `build.ps1` | 默认 `-Version`（写入 `utils.Version` ldflags），例如 `v26.60-cml` | 每次 |
| 20 | `core/lib/src/bedrock/bedrocktool.dart` → `BedrockToolInfo` | `supportedVersion`、`gameVersion`、`protocol`（CML 界面横幅显示，`core/test/bedrocktool_test.dart` 会与 `info.go` 比对） | 每次 |
| 21 | 本目录新增 `V<版本>_ADAPTATION.md` + 本文“版本矩阵” | 记录 | 每次 |

---

## 1. 获取新版本信息

按优先级依次查：

1. **Mojang 官方协议文档**
   - 变更记录：<https://mojang.github.io/bedrock-protocol-docs/changelog/>
   - 仓库：<https://github.com/Mojang/bedrock-protocol-docs>（`json/` 下有每个包的字段定义，`html/` 有可读版；比较两个 tag 的 diff 最直观）
   - 记录：新协议号、新增/删除包、每个包的字段增删、类型变化（`varint` ↔ `uint32 LE`、`bool` ↔ `optional`）。
2. **gophertunnel 上游**
   - Releases：<https://github.com/Sandertv/gophertunnel/releases>（每个 release 标题通常就是“Support for 1.xx.yy”）
   - 关键提交：`git log -- minecraft/protocol/info.go`
   - 参考包已离线保存在 `D:\Server\Others\Sample\BedrockTools\work\official-module-reference\`（当前 `gophertunnel-v1.62.0`、`dragonfly-v0.11.5`）；新版本下载后放到同一目录。
3. **dragonfly 上游**：<https://github.com/df-mc/dragonfly>（`server/world/block_states.nbt`、`vanilla_items.nbt`、配方数据的更新提交）
4. **Minecraft 官方更新日志**：<https://feedback.minecraft.net/hc/en-us/sections/360001186971-Release-Changelogs>（判断是否热修复、是否有网络相关修复）
5. **PrismarineJS/bedrock-protocol**、**CloudburstMC/Protocol**：交叉验证字段（尤其 Mojang 文档延迟时）
6. **Creator 文档**：<https://github.com/MicrosoftDocs/minecraft-creator>（`format_version`、`min_engine_version` 变化）

> 判断协议号：Mojang changelog 首行；或抓真实客户端登录包（`capture` 子命令连接任意服务器，`RequestNetworkSettings.ClientProtocol`）；或 gophertunnel `info.go`。

---

## 2. 版本矩阵（每次升级先填写）

复制下表到新的 `V<版本>_ADAPTATION.md`，并在本文末尾“历史矩阵”追加一行：

| 项目 | 旧值 | 新值 | 来源 |
|---|---|---|---|
| Minecraft 版本 | 26.52 | | feedback.minecraft.net |
| `CurrentVersion` | `1.26.52` | | info.go |
| `CurrentProtocol` | 2193 | | Mojang changelog |
| 方块版本 `CurrentBlockVersion` | 1.21.60.33 / 18168865 | | dragonfly 上游 / 抓包 StartGame |
| 行为包 `format_version` | 1.26.50 | | Creator 文档 |
| 内置原版资源包 | `d34cfa4b-…_1.26.40` | | 抓包 ResourcePackStack |
| gophertunnel 对照上游 | v1.62.0 | | GitHub release |
| dragonfly 对照上游 | v0.11.5 | | GitHub |
| go-nethernet | v1.0.20（本地 fork） | | go.mod |
| Go 工具链 | go1.27.0 | | `go version` |
| CML 构建标记 `utils.Version` | `v26.52-cml` | | build.ps1 |

---

## 3. 决策：热修复还是协议升级

| 情况 | 判定依据 | 处理 |
|---|---|---|
| A. 热修复，协议号不变，线格式不变 | changelog 无协议条目；抓包协议号相同 | 只改 `CurrentVersion`、`build.ps1 -Version`、`BedrockToolInfo.gameVersion/supportedVersion`；跑测试门禁第 1、2 级 |
| B. 热修复，协议号不变，**但线格式变了**（26.44 就发生过） | 同协议号，但旧代码解码报 `unread bytes`/panic | 按协议升级处理字段；在 `conn.go` 登录版本门槛里拒绝旧小版本（参考现有 `patchVer < 50` 分支） |
| C. 协议号变化（常规版本） | 新协议号 | 完整流程（第 4–7 节） |
| D. 只有内容变化（新方块/物品），协议号不变 | 世界下载出现 unknown block / 物品丢失 | 更新 dragonfly 注册表数据（第 5 节） |
| E. 服务端认证/信令变化 | 登录或 Realms 连接失败，但协议包本身正常 | 只改 `utils/auth`、`utils/franchise`、`go-nethernet`（第 6 节） |

---

## 4. 协议层更新（gophertunnel fork）

### 4.1 本 fork 与上游的差异先摸清

本仓库里的 `gophertunnel/`、`dragonfly/`、`go-nethernet/`、`go-raknet/` **不是** git 子模块，而是带 fork 专用 API 的源码副本（go.work 引用）。**绝不能整包替换为上游**。比对方法：

```powershell
# 1) 准备上游两个版本（旧对照基线 + 新目标）
cd D:\Server\Others\Sample\BedrockTools\work\official-module-reference
git clone https://github.com/Sandertv/gophertunnel.git gophertunnel-upstream
cd gophertunnel-upstream
git tag --sort=-creatordate | Select-Object -First 5     # 找到新 tag，例如 v1.63.0

# 2) 上游在两个版本之间改了什么（协议部分）
git diff v1.62.0 v1.63.0 --stat -- minecraft/protocol
git diff v1.62.0 v1.63.0 -- minecraft/protocol > ..\gt-1.62-1.63.diff

# 3) 本 fork 相对上游基线改了什么（避免把 fork 修改覆盖掉）
git diff --no-index --stat v1.62.0-tree  D:\Server\Others\ChthollyMinecraftLauncher_CML\tools\bedrocktool\gophertunnel
#   （v1.62.0-tree = git worktree add ..\v1.62.0-tree v1.62.0）
git diff --no-index v1.62.0-tree\minecraft\protocol ...\tools\bedrocktool\gophertunnel\minecraft\protocol > ..\fork-vs-1.62.diff

# 4) 把上游 diff 打到 fork 上（三方合并，冲突手工处理）
cd D:\Server\Others\ChthollyMinecraftLauncher_CML\tools\bedrocktool\gophertunnel
git apply --3way --directory=gophertunnel ..\..\..\..\Sample\BedrockTools\work\official-module-reference\gt-1.62-1.63.diff
#   不在 git 仓库内时用：  patch -p1 --dry-run < gt-1.62-1.63.diff  然后去掉 --dry-run
```

fork 专用、**必须保留** 的部分（历次适配加入）：

- `minecraft/conn.go`：26.44/26.50 线格式门槛、空文本 Disconnect 保留 reason 数字
- `minecraft/network_identity*.go`、`dial.go`：NetherNet `a=identity`、多会话 token 复用
- `minecraft/protocol/skin.go`：v2168 皮肤编解码（hands 单复数、persona tint 名称转换）
- `minecraft/protocol/packet/crafting_data.go`：1.26.40 起的分类型配方向量
- `minecraft/realms/`：Realms join 响应保留 `NetworkProtocol`
- `minecraft/resource/`：`UUID_version` 兼容

### 4.2 版本常量

`gophertunnel/minecraft/protocol/info.go`：

```go
const (
	CurrentProtocol = 2193          // ← 新协议号
	CurrentVersion  = "1.26.52"     // ← 新版本，必须是 1.x.y 三段式（login/data.go 的 checkVersion 只接受数字和点）
)
```

`CurrentVersion` 被以下位置引用（自动跟随，但需检查行为）：`minecraft/dial.go`（ClientData.GameVersion）、`minecraft/auth/minecraft.go` 与 `realms/realms.go`（`Client-Version` 头）、`service/discovery.go`、`utils/franchise/discovery/discovery.go`（discovery URL）、`utils/auth/account.go`（MCToken 过期判定）、`dragonfly/server/world/mcdb/leveldat/*`（存档版本）、`ui/gui/gui.go`（窗口标题）。

### 4.3 逐包字段核对清单

对 Mojang changelog 中列出的每一个变更包，打开 `gophertunnel/minecraft/protocol/packet/<snake_name>.go`，逐项核对 `Marshal(io protocol.IO)`：

- [ ] **字段顺序** 与 Mojang `json/` 定义完全一致（新增字段常插在中间，不一定在末尾）
- [ ] **整数编码**：`io.Varint32` / `io.Varuint32` / `io.Varint64` / `io.Varuint64`（变长） vs `io.Int32` / `io.Uint32` / `io.Int64`（小端定长） vs `io.BEInt32`；Mojang 文档里 `varint32`/`unsigned varint`/`int32 LE` 的区别
- [ ] **ActorRuntimeID**（varuint64）与 **ActorUniqueID**（varint64）别混
- [ ] **浮点**：`io.Float32` vs `io.ByteFloat`（旋转角用 1 字节）
- [ ] **布尔**：`io.Bool`；Mojang 改成 optional 时变为 `protocol.OptionalFunc(io, &x, io.Float32)`（`Optional[T]` 前缀 1 字节 bool）
- [ ] **嵌套 Optional**：如 Scoreboard remove entry 是双层 Optional（26.44 起）
- [ ] **数组长度**：`protocol.Slice`（varuint32 长度）/ `SliceUint8Length` / `SliceUint32Length`（LE uint32）/ `FuncSlice` / `SliceOfLen`（长度在别处给出）
- [ ] **字符串**：`io.String`（varuint32 长度）vs `io.StringUTF`（int16 长度，仅 login）vs `io.ByteSlice`
- [ ] **UUID**：`io.UUID`（16 字节，两段 LE int64，注意字节序）
- [ ] **枚举**：新增常量补到对应 `const` 块；值是 varint 还是 byte
- [ ] **NBT**：`io.NBT(&m, nbt.NetworkLittleEndian)` vs `nbt.LittleEndian`
- [ ] **BlockPos**：`io.UBlockPos`（y 为 varuint32）vs `io.BlockPos`（y 为 varint32）
- [ ] **ItemStack / ItemInstance**：`protocol/item_stack.go`、`item.go`；网络 ID 用 varint32
- [ ] 有 **服务端/客户端方向不同布局** 的包（`if pk.ID() ...` 或 `io` 方向判断）两边都核对
- [ ] **新包**：在 `packet/id.go` 正确位置追加 `IDXxx`（`iota` 顺序，空号用 `_` 占位），在 `packet/pool.go` 的 `serverOriginating` / `clientOriginating` 映射中注册
- [ ] 被 **删除** 的包：从 pool 移除，但保留结构体（代理可能还要解码旧回放）
- [ ] 调用方同步：`grep -rn "packet.<Name>{" ..\..\` 找到 `handlers/`、`utils/proxy/`、`dragonfly/server/session/` 中构造该包的位置，补新字段默认值

重点高频变更包（历次都动过）：`StartGame`、`PlayerAuthInput`、`MoveActorDelta`、`InventoryTransaction`、`ItemStackRequest/Response`、`ResourcePacksInfo`、`ResourcePackStack`、`CraftingData`、`LevelChunk`、`SubChunk`、`PlayerList`、`AddActor`/`AddPlayer`、`CameraPresets`/`CameraInstruction`、`BossEvent`、`SetScore`、`Text`、`BiomeDefinitionList`、`ItemRegistry`。

### 4.4 登录与网络设置

- `protocol/login/data.go`：`ClientData` 结构体字段（JSON 名大小写敏感）、`Validate()` 里的范围检查（例如 `DeviceOS` 1–15，新平台会扩展）。
- `protocol/login/request.go`：链/令牌格式（2024 起有 `Certificate` + `Token` 两种）。
- `packet/request_network_settings.go`（客户端第一个包，含协议号；**不压缩**）、`packet/network_settings.go`（压缩阈值、算法、客户端节流）。
- `minecraft/conn.go` 第 ~796 行：`ClientProtocol > CurrentProtocol` 的报错文本；第 ~853–875 行：同协议号线格式门槛，**协议号变化后要更新版本判断**（例如改成 `patchVer < 60`）或删除过时分支。

---

## 5. 内容层更新（dragonfly fork）

1. **方块状态**：用上游 dragonfly 新版本的 `server/world/block_states.nbt` 替换 `dragonfly/server/world/block_states.nbt`；或用 pmmp/BedrockData 的 `canonical_block_states.nbt` 转换。
2. **方块版本**：`dragonfly/server/world/chunk/encode.go` 中 `CurrentBlockVersion`（整数 = `major<<24 | minor<<16 | patch<<8 | revision`，例如 1.21.60.33 → 18168865）。可从抓包 `StartGame` 的方块调色板或 BedrockData 的 `block_state_meta_map` 版本得到。
3. **物品**：`dragonfly/server/world/vanilla_items.nbt`（同时被 `dragonfly/server/server.go` embed）、`dragonfly/server/item/creative/creative_items.nbt`、配方 `dragonfly/server/item/recipe/*.nbt`、`item_tags.json`。
4. **状态属性改名**：26.50 起窗格/铁栏杆/铜栏杆/栅栏/绊线/楼梯的连接状态改名，映射在 `dragonfly/server/block/connection_properties.go`，回归测试 `dragonfly/server/block/connection_properties_test.go`。新版本若再改名，在这里加映射并补测试。
5. **网络方块哈希**：`dragonfly/server/world/network_block_hash.go`；BedrockTool 的 `utils/merge/block_registry.go` 通过 `go:linkname` 调用它，函数签名改了要同步（测试 `utils/merge/block_registry_test.go`）。
6. **维度高度**：`dragonfly/server/world/dimension.go`（Overworld `[-64, 319]`）。
7. **行为包**：`utils/behaviourpack/bp.go` 的 `behaviourPackFormatVersion`；`utils/behaviourpack/{entity,custom_block}.go` 使用它。
8. **内置原版资源包**：`utils/proxy/resourcepacks/resourcepacks.go` 的 `exemptedPacks` 与 `gophertunnel/minecraft/conn.go` 的 `exemptedPacks`（UUID `d34cfa4b-2ad1-453d-a0db-668b429a3ea0`，版本跟随原版包，例如 `1.26.40`）。抓 `ResourcePackStack` 可确认。

---

## 6. 连接层（NetherNet / RakNet / Realms 信令）

- **RakNet**：`go-raknet/`，协议版本几乎不变；若官方升级 RakNet 协议号，改 `go-raknet` 中的 `protocolVersion` 常量。
- **NetherNet（WebRTC）**：`go-nethernet/`（`dial.go`、`conn.go`、`identity.go`、`signal.go`），桥接在 `utils/proxy/nethernet.go`。
- **信令**：`utils/franchise/signaling/`（`jsonrpc.go` 新版 `/ws/v1.0/messaging/connect`，旧版 `conn.go`/`message.go`）；默认全局主机 `signal.franchise.minecraft-services.net`；区域节点 NXDOMAIN 回退在 `utils/connectinfo/connect_info.go`。
- **认证/发现**：`utils/franchise/{discovery,authservice,playfab,gatherings}`、`utils/auth/`。discovery URL 带 `CurrentVersion`，新版本未上线前 discovery 可能返回 404 —— 这是正常现象，等 Mojang 服务端开放后重试。

---

## 7. 测试门禁

环境（与 `build.ps1` 相同）：

```powershell
$GoRoot   = 'D:\Server\Others\Sample\BedrockTools\go'
$env:GOROOT=$GoRoot; $env:Path="$GoRoot\bin;$env:Path"
$env:GOTOOLCHAIN='local'; $env:GOPROXY='off'; $env:GOSUMDB='off'
$env:GOWORK="$PWD\go.work"
$env:GOMODCACHE='D:\Server\Others\Sample\BedrockTools\work\go-mod-cache'
cd D:\Server\Others\ChthollyMinecraftLauncher_CML\tools\bedrocktool
```

> 新增依赖时需要临时 `GOPROXY=https://goproxy.cn,direct` 下载到同一 `GOMODCACHE`，然后改回 `off` 再验证一次离线构建。

**第 1 级：编译**（必过）

```powershell
go vet ./cmd/bedrocktool
go build ./cmd/bedrocktool ./handlers/... ./utils/...    # 多包构建只做编译检查，不产出 exe
go build ./gophertunnel/minecraft/... ./dragonfly/server/...
```

注意：`./subcommands/...` 和 `./gophertunnel/...` 不能整体枚举 —— 前者会读到下面的 git-crypt 密文，后者包含过时的示例 `gophertunnel/main.go`（`unknown field TokenSource`，与工具无关）。`cmd/bedrocktool` 已经导入了 `subcommands`，因此第一行已覆盖子命令编译。

不要跑 `go test ./...`：`subcommands/resourcepack-d/resourcepack-d.go`（子目录里的那个，不是 `subcommands/resourcepack-d.go`）是 git-crypt 密文（`GITCRYPT` 开头），只在 `-tags packs` 下被 `subcommands/resourcepack-stub.go` 导入（`packs` 命令本身是明文，正常编译）；直接枚举会报 `unexpected NUL in input`。**不要修改或删除该密文文件，也不要传 `packs` 标签。**

**第 2 级：单元测试**（必过）

```powershell
go test -count=1 ./cmd/bedrocktool
go test -count=1 ./gophertunnel/minecraft            # TestNewDisconnectError, network identity
go test -count=1 ./dragonfly/server/world ./dragonfly/server/block   # TestNetworkHash, TestConnectedStateRoundTrip
go test -count=1 ./utils/merge                       # TestNetworkBlockHashLink（go:linkname ABI）
go test -count=1 ./utils/proxy/... ./utils/connectinfo ./utils/franchise/signaling ./utils/auth
go test -count=1 ./go-nethernet/...
```

已知与协议无关的失败（2026-10 状态，不阻断发布）：

- `gophertunnel/minecraft/resource` `TestVersion`：`1.0.0-test` 版本解析，fork 前就存在
- `utils` `TestInvalidJsonFix`：HuJSON 前导零用例
- `go-raknet` `TestPing*`：需要外网访问 `mco.mineplex.com`

**第 3 级：CML 侧**

```powershell
cd ..\..\core;     dart test test/bedrocktool_test.dart     # 含 info.go ↔ BedrockToolInfo 比对、真实 exe help/flag 解析
cd ..\launcher;    flutter analyze lib/pages/bedrock_tools_page.dart
```

`BtCommands` 表与 exe 的 `<cmd> -h=true` 输出会被测试比对；子命令新增/改名的 flag 要同步到 `core/lib/src/bedrock/bedrocktool.dart` 的 `BtCommands` 和页面的 `_tools()`。

**第 4 级：实机**（发布前）

| 场景 | 命令 | 通过标准 |
|---|---|---|
| 公共服务器下载世界 | `bedrocktool worlds -address=<服务器>` | 游戏进入、区块保存、`worlds\` 下生成可在新版客户端打开的存档 |
| 皮肤 | `bedrocktool skins -address=…` | `skins\<host>\` 有 png/geometry |
| 抓包回放 | `bedrocktool worlds -address=captures\xxx.pcap2` | 回放解码无 `unread bytes` |
| Realm | `bedrocktool list-realms`，`worlds -address=realm:<名>` | 登录、信令、DataChannel 打开、进服 |
| 精选服务器 | `-address=experience:<id>` 或 `gathering:<名>` | 进服 |
| 首次登录 | 删除 `%APPDATA%\CML\bedrocktool\token.json` 后运行 | CML 弹出设备码对话框，登录后继续 |

---

## 8. 连接故障排查表

| 现象（控制台 / bedrocktool.log） | 层 | 优先检查 |
|---|---|---|
| `incompatible protocol version: expected X, got Y` | 协议号 | `info.go` 未更新，或客户端版本比工具新/旧 |
| `incompatible protocol game version: expected 1.26.50 or newer` | conn.go 门槛 | 客户端是旧小版本；或门槛条件没随新版本更新 |
| 游戏提示“需要更新客户端/服务器已过期” | 协议号 | 同上；检查 `RequestNetworkSettings` 抓包 |
| `unread bytes` / `panic: ... index out of range` 解码错误 | 包布局 | 第 4.3 节清单；看日志中的包名逐字段对比 |
| 进服后卡在“正在生成世界” | StartGame / ItemRegistry / BiomeDefinitionList | 字段顺序、方块调色板、`CurrentBlockVersion` |
| 世界保存后方块全是 unknown/更新方块 | dragonfly 注册表 | `block_states.nbt`、状态改名映射 |
| `mctoken for older version, refreshing` 循环 | 认证 | `CurrentVersion` 与服务端签发版本；删 `token.json` 重登 |
| discovery 404 | 服务发现 | 新版本服务端未开放，稍后重试；检查 discovery URL |
| `missing port in address` | Realms | GUID/NetworkID 被当成 host:port |
| signaling `no such host` | 信令 | 区域节点回退到 `signal.franchise.minecraft-services.net` |
| `Unable to deliver message to the target` | 信令 | 目标 Realm 未在线/区域不对（26.52 起会直接报错退出） |
| NetherNet code 37 | 身份 | `a=identity`、issuer 尾斜杠、P-384 私钥与登录会话一致性 |
| `use of closed network connection` | DataChannel | DCEP 打开时序；Disconnect reason 映射 |
| 资源包下载卡住 | 资源包 | `UUID_version`、分块 Flush、`exemptedPacks` 版本 |
| 本地游戏连不上代理 | 网络 | 防火墙放行 UDP 19132、`-listen` 地址、主机/手机同网段 |

---

## 9. 构建、发布与回滚

### 9.1 构建

```powershell
# 本目录
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version v26.60-cml
#   参数：-GoRoot <Go>  -ModCache <模块缓存>  -Version <utils.Version>  -SkipTests
#   输出：out\bedrocktool.exe、out\BUILD_INFO.json（大小、SHA256、Go 版本）
.\out\bedrocktool.exe help     # 第一行应为 "Bedrocktool Version v26.60-cml"
```

`build.ps1` 不使用 `gui`/`packs` 标签；CML 用户通过启动器内的「基岩版工具」页面使用（原 Gio GUI 不再随 CML 发布）。

### 9.2 通过 CML 发布

1. 更新 `core/lib/src/bedrock/bedrocktool.dart` 的 `BedrockToolInfo`（`supportedVersion`、`gameVersion`、`protocol`），运行 `dart test test/bedrocktool_test.dart`。
2. 新子命令/flag：同步 `BtCommands` 与 `launcher/lib/pages/bedrock_tools_page.dart` 的 `_tools()`，新增 UI 文案加到 `launcher/lib/i18n/strings_en_bedrock.dart`，跑 `flutter test test/i18n_test.dart`。
3. 仓库根目录 `build.ps1` 会调用本目录 `build.ps1` 并把 `out\bedrocktool.exe` + `LICENSE` 复制到 `dist\CML\tools\bedrocktool\`（运行时路径 `Bundled.bedrocktool`，可用 `CML_BUNDLE_DIR` 覆盖做本地测试）。
4. 写 `V<版本>_ADAPTATION.md`，更新本文第 0 节“当前状态”和末尾矩阵。
5. 发布 CML 新版本（自更新会替换 `tools\bedrocktool\bedrocktool.exe`；用户的 `token.json`、下载的世界在 `%APPDATA%\CML\bedrocktool`，不受影响）。
6. GPL-3：发布说明附源码位置（本仓库 `tools/bedrocktool`）。

### 9.3 回滚

- 保留上一版 `out\BUILD_INFO.json` 与 exe（发布前复制到 `D:\Server\Others\Sample\BedrockTools\outputs\cml-<旧版本>\`）。
- 回滚 = 恢复旧源码（VCS 回退本目录与 `core/lib/src/bedrock/bedrocktool.dart`）→ `build.ps1 -Version <旧版本>` → 校验 SHA256 与旧 `BUILD_INFO.json` 一致（`-trimpath` + 同一工具链可复现）→ 重新发布 CML。
- 不同协议号无法互通：回滚后用户需要使用旧版本游戏客户端，发布说明中要写明。

---

## 10. 升级记录模板（`V<版本>_ADAPTATION.md`）

```markdown
# BedrockTool v<版本> 适配记录
## 目标（版本矩阵，第 2 节表格）
## 判定（第 3 节 A–E）
## 改动
- 协议：<包名：字段变化>
- 内容：<注册表/方块版本>
- 连接：<信令/认证>
## 验证（第 7 节各级命令及结果，已知失败）
## 官方依据（链接）
```

## 历史矩阵

| 日期 | Minecraft | 协议 | `CurrentVersion` | 方块版本 | 行为包 | 构建标记 | 记录 |
|---|---|---|---|---|---|---|---|
| 2026-08 | 1.21.124 → 26.44 | 860 → 2168 | 1.26.44 | — | 1.26.40 | v26.44-adapted | V26.44_ADAPTATION.md |
| 2026-09 | 26.50 / 26.52 | 2193 | 1.26.52 | 1.21.60.33 | 1.26.50 | v26.52-adapted-signaling1 | V26.52_ADAPTATION.md |
| 2026-10 | 26.52（CML 集成） | 2193 | 1.26.52 | 1.21.60.33 | 1.26.50 | v26.52-cml | 本文；CLI 退出前刷新 stdout 管道（`cmd/bedrocktool/log.go`） |
