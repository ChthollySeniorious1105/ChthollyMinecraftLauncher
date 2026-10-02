# BedrockTool 适配更高 Minecraft Bedrock 版本：详细流程

> 适用对象：基于 `bedrocktool-master`/现有 BedrockTool 分支，升级到新的 Minecraft Bedrock 版本。本文记录本工作区从 1.21.124（协议 860）迁移到 1.26.44（协议 2168）的实际流程，可复用于后续版本。
>
> 记录日期：2026-08-31

## 1. 建立版本工作区

1. 保留原始输入，不直接在唯一副本上修改。
2. 为每个版本建立独立目录，例如：

```text
source/bedrocktool-v1.21.124-reusable   # 可复用旧版本
source/bedrocktool-v26.44               # 当前适配版本
minecraft-project/bedrocktool-v26.44    # 不可变原始副本
backups/bedrocktool-v1.21.124-archive-YYYYMMDD
outputs/                                  # 发布文件
work/                                     # Go 工具链、缓存、测试副本
```

3. 记录源代码文件数、目录树 SHA-256、Git 提交/上游依赖版本。
4. 归档旧版本时同时保存完整源代码、发布目录、清单、SHA256SUMS 和说明文档。

## 2. 确定目标版本矩阵

建立一张版本矩阵，至少包括：

| 项目 | 旧值 | 新值 |
|---|---:|---:|
| Minecraft 版本 | 1.21.124 | 1.26.44 |
| NetworkProtocol | 860 | 2168 |
| Gophertunnel | 旧 fork/API | v1.59.0 基线 |
| Go | 1.27.0 | 1.27.0 |
| 资源包 format_version | 按旧版本 | 1.26.40（26.44 热修复兼容） |

不要只替换版本字符串；协议号、编码布局、依赖 API 和连接流程必须分别验证。

## 3. 更新协议层（优先处理）

### 3.1 版本常量

检查并更新 `gophertunnel/minecraft/protocol/info.go`：

```go
const CurrentVersion = "1.26.44"
const CurrentProtocol = 2168
```

同步所有版本判断、登录校验、NetworkSettings 和版本兼容表。

### 3.2 数据包结构

对比目标版本上游 gophertunnel/bedrock-protocol 变更，重点检查：

- `PlayerList`
- `MoveActorDelta`
- `LevelChunk`、`SubChunk`
- blob cache
- scoreboard remove-entry 的嵌套 Optional
- skin、手臂尺寸、颜色字段
- login ClientData、DeviceID、NetworkProtocol
- StartGame、ResourcePacksInfo、ResourcePackStack

每一个字段都要确认：字段顺序、VarInt/LE、Optional 层数、数组长度编码、UUID 编码和枚举值。

### 3.3 注册表与行为层

同步 Dragonfly fork 的方块/物品注册表及 session 层调用。不要无条件替换成上游 master；BedrockTool 依赖的 fork API 可能不兼容。优先采用：

1. 保留现有 fork。
2. 移植目标版本新增的协议注册项。
3. 为新增状态写最小回归测试。

## 4. 更新 NetherNet、RakNet 和 Realms 连接

这是高版本最容易出现“能编译但无法连接”的部分。

### 4.1 依赖/API

确认 `go.mod` 中 go-nethernet、go-raknet、gophertunnel 的版本和本地 replace。若 API 引入 `context.Context` 或 cancel cause，要沿调用链传递，不要用空 context 或吞掉错误。

### 4.2 Realms/精选服务器流程

按以下顺序检查：

1. 解析 join 响应中的 `NetworkProtocol`，不要把 `NETHERNET_JSONRPC` GUID 当作 RakNet `host:port`。
2. 使用 `/ws/v1.0/messaging/connect` 建立 JSON-RPC WebSocket。
3. 正确处理区域 signaling 节点；NXDOMAIN 时回退全局节点并重新生成 session/request ID。
4. Realms 使用完整 ICE candidate SDP，关闭 trickle ICE。
5. NetherNet 拨号只传真实 Network ID，不拼接界面内部前缀。
6. 复用 Minecraft 登录阶段的 P-384 私钥和多会话 token，生成并验证 `a=identity`。
7. 等待 Reliable 和 Unreliable DataChannel 都收到 DCEP open，再把连接交给 Minecraft 层。
8. 首个 `RequestNetworkSettings` 必须在通道可发送后发出。
9. 服务端空文本 Disconnect 仍保留 wire reason 数字，避免退化成 `use of closed network connection`。

### 4.3 错误日志定位表

| 现象 | 优先检查 |
|---|---|
| `missing port in address` | 是否误把 GUID/Network ID 当 host:port |
| signaling `no such host` | 区域 DNS 回退、节点配置、重新生成 request ID |
| NetherNet code 37 | `a=identity`、issuer、token、私钥和登录会话是否一致 |
| `use of closed network connection` | DataChannel DCEP 时序、关闭原因映射 |

## 5. 资源包策略

如果服务器不能安装材质包，可明确采用“忽略材质包转换”策略：

- 保留资源包 UUID/`UUID_version` 解析。
- 代理正确转发服务端资源包标识。
- 不增加或启用材质包转换器。
- 资源包下载失败与协议连接失败分开记录。

## 6. 代码修改顺序

推荐按此顺序提交小步变更：

1. 版本常量和登录版本校验。
2. protocol 数据包/编码布局。
3. registry、session、chunk/level 数据。
4. go-nethernet API 迁移。
5. Realms signaling 和 WebSocket JSON-RPC。
6. DataChannel 时序与错误映射。
7. 资源包 UUID 兼容。
8. CLI/GUI 版本信息、构建脚本和发布元数据。

每一步都执行格式化、编译和最小测试，避免把协议错误与连接错误混在一个大补丁中。

## 7. 测试门禁

### 7.1 静态检查

```powershell
$env:GOTOOLCHAIN='local'
$env:GOPROXY='off'
go test ./cmd/bedrocktool
go test ./gophertunnel/...
go test ./dragonfly/...
go test ./go-raknet/...
go test ./go-nethernet/...
```

含 git-crypt 密文或生成的 `.syso` 文件时，先按项目规则排除，避免把“源文件不可解析”误判为协议回归。

### 7.2 目标专项测试

至少覆盖：

- TargetVersion/TargetProtocol
- disconnect reason fallback
- block registry vanilla states
- merge/hash ABI
- resource-pack UUID 与 `UUID_version`
- Realms JSON-RPC request/result/ACK
- signaling NXDOMAIN 回退
- `a=identity` 签名验证
- trickle/non-trickle 两种 DataChannel 打开时序（建议重复 30 次）
- CLI `help` 和 GUI 启动烟测

### 7.3 连接实测

记录每次实测的：目标地址、区域节点、时间、客户端版本、协议号、首个错误、完整日志。不要只记录“连接失败”；要区分 DNS、TLS/WebSocket、ICE、DCEP、RakNet 和 Minecraft 层。

## 8. 构建 CLI/GUI

Windows amd64 示例：

```powershell
$env:GOTOOLCHAIN='local'
go build -buildvcs=false -trimpath `
  -ldflags '-s -w -X github.com/bedrock-tool/bedrocktool/utils.Version=vX.Y.Z-adapted -X github.com/bedrock-tool/bedrocktool/utils.CmdName=bedrocktool' `
  -o outputs/bedrocktool-vX.Y.Z-windows-amd64.exe ./cmd/bedrocktool
```

GUI 需使用与 CLI 相同的源码、Go 版本、依赖锁定和版本 ldflags；构建后执行：

```powershell
outputs/bedrocktool-vX.Y.Z-windows-amd64.exe help
```

检查输出中的版本字符串和 `Available Commands:`，再对 CLI、GUI、source ZIP、release ZIP 计算 SHA-256。

## 9. 归档与可回滚发布

每次版本切换必须生成：

- `ARCHIVE_MANIFEST.json`
- `README.md`
- `SHA256SUMS.txt`
- `VERIFICATION.txt`
- `MODIFIED_FILE`：记录活动工作区状态
- `DIFF_FILE`：记录旧状态到新状态的字段差异
- 可执行 `ROLLBACK.sh`（调用 PowerShell 实现安全替换）

回滚流程应在独立副本上验证：

1. 复制活动版本到 `work/` 测试目录。
2. 执行 rollback 脚本。
3. 验证旧版本目录、release 目录、状态文件和 marker。
4. 重新运行 `go test ./cmd/bedrocktool`。
5. 重新计算目录树哈希。
6. 确认归档源、发布文件和元数据哈希未变化。
7. 确认真实活动工作区未被测试副本修改。

## 10. 常见失败与处理

- **版本号已改但登录失败**：检查 ClientData/NetworkSettings 中的协议号和版本校验。
- **编译通过但 Realms 失败**：检查 signaling URL、区域回退、JSON-RPC ACK 和 DataChannel open 时序。
- **code 37**：检查登录 token、P-384 私钥、issuer、`a=identity` 和多会话复用。
- **`missing port`**：检查地址类型，GUID/Network ID 不能直接传给 UDP dial。
- **材质包错误**：若目标服务器不能装材质包，跳过转换；只保证 UUID 标识和协议流程正确。
- **`go test ./...` unexpected NUL**：检查 git-crypt 密文文件，按构建规则排除，不要修改密文。
- **GUI 可启动但 CLI 版本不一致**：统一 ldflags、输出目录和发布脚本。

## 11. 交付检查清单

- [ ] 旧版本原始哈希已保存。
- [ ] 新版本协议号、版本号和依赖矩阵已记录。
- [ ] protocol/registry/session/NetherNet/Realms 均有专项测试。
- [ ] CLI、GUI 启动烟测通过。
- [ ] source/release ZIP 可解压且 SHA-256 已记录。
- [ ] 归档清单、差异文件、验证文件和回滚脚本已生成。
- [ ] 回滚脚本在独立副本上通过，归档与活动工作区状态正确。
- [ ] 发布说明注明资源包转换策略及已知限制。

## 12. 本工作区示例结果

本次实际迁移结果：

- 活动版本：`v26.44-adapted` / Minecraft `1.26.44` / protocol `2168`
- 活动源：`source/bedrocktool-v26.44`
- 归档版本：`v1.21.124-reusable` / protocol `860`
- 归档目录：`backups/bedrocktool-v1.21.124-archive-20260827`
- v1.21.124 全源代码：1454 文件，树哈希 `aec67e1cdbe1973ad12fe2235a8d08bbfc3b748bed0d0b1367e3d241e8a45b16`
- v26.44 活动源：1510 文件，树哈希 `7e3d2313119a57c1e8e267b8c102465f9c587f00610a0bc44ba24eaf38b9b3d9`
- baseline、modified、rollback、artifact reopen 验证均为 PASS。
---

## 工作区 v26.52 适配记录（2026-09-27）

本次以工作区现有的 v26.45 清洁副本为输入，独立维护，不从外部仓库同步旧版本内容。官方协议记录显示 26.45 使用 2169，26.50/26.51 使用 2193，26.52 热修复不增加协议字段；本工作区输入文件实际标记为 1.26.44/2168，因此保留了 `work/baseline-26.45-as-provided` 后直接完成 2193 布局适配。

目标状态：Minecraft Bedrock Edition 26.52、协议 2193、协议代码版本 `1.26.52`、内容方块版本 `1.21.60.33`（18168865）。本次同时更新了协议包、方块状态数据、物品标签、维度高度图、行为包格式，以及窗格/栏杆/栅栏/绊线/楼梯的 26.50 状态映射。构建脚本输出到 `outputs/bundle-26.52`，并在构建前清理旧的 26.44、26.45、26.50 CLI/GUI 可执行文件。

验证命令：

```powershell
go test ./gophertunnel/minecraft/protocol/...
go test ./dragonfly/...
go test ./dragonfly/server/block
go test ./cmd/bedrocktool ./handlers/...
powershell -ExecutionPolicy Bypass -File .\build_bedrocktool_bundle.ps1 -Mode windows -BuildGui
```

官方依据：[Mojang Bedrock 协议变更记录](https://mojang.github.io/bedrock-protocol-docs/changelog/)、[26.50 变更记录](https://feedback.minecraft.net/hc/en-us/articles/48826825649933-Minecraft-Bedrock-Edition-26-50-Changelog-Wilderness-Bound)、[26.52 热修复记录](https://feedback.minecraft.net/hc/en-us/articles/49175370527501-Minecraft-Bedrock-Edition-26-52-Hotfix-Changelog)。

### v26.52 JSON-RPC 信令运行时修复（2026-09-27）

构建标记为 `v26.52-adapted-signaling1`。本地用带有 `Code`/`Message` 的投递失败
服务信封复现了 `parse ConnectionID ... parsing "to"`：旧解析器把 JSON 内的普通
错误文本按 NetherNet 信号拆分，打印警告后仍然等待握手。用户日志没有原始消息，
实际服务端错误码尚待新程序重试确认。

现在会识别服务错误、保留错误码和原文后结束信令等待；正常投递回执会被单独识别，
未知 JSON 消息仍报告格式错误。区域节点 DNS 不存在时继续回退到全局信令节点。
signaling、proxy、connectinfo 测试通过，包含本地 WebSocket 投递失败及正常消息交换测试。
