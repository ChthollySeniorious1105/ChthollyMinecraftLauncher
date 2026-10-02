# Pulse 架构说明（ARCHITECTURE）

> 写给之后维护 Pulse 的人（包括其他 AI 会话）。重点说明各模块边界、协议、安全设计，以及**如何适配新的显卡 / 驱动 / ONNX Runtime 版本**（§6）。
> 文中路径均相对于仓库根目录 `D:\Server\Others\Pulse`。

---

## 1. 总览

```
┌───────────────────────── Windows 客户端 pulse.exe (Flutter) ─────────────────────────┐
│  UI (lib/screens, lib/widgets, lib/theme)                                            │
│    └─ AppState (lib/state/app_state.dart) ── Settings (DPAPI 令牌, settings.json)     │
│         ├─ Connection (lib/net) ──── TCP + X25519/ChaCha20-Poly1305 ────────┐        │
│         └─ Native (lib/native/native.dart, dart:ffi)                          │        │
│              └─ pulse_native.dll (client/native, C++)                        │        │
│                   ├─ miniaudio/WASAPI 采集+播放、设备选择、音量               │        │
│                   ├─ RNNoise 降噪 + VAD / 按键说话门限                        │        │
│                   ├─ 变声：DSP（变调/机器人）| AI（ONNX Runtime + GPU）       │        │
│                   ├─ Opus 编解码、抖动缓冲、混音、提示音                      │        │
│                   ├─ 全局快捷键（WH_KEYBOARD_LL / WH_MOUSE_LL）              │        │
│                   └─ DPAPI                                                    │        │
└──────────────────────────────────────────────────────────────────────────────┼────────┘
                                                                               │
┌──────────────────── 服务端 pulse_server.exe (Dart AOT) ───────────────────────┴───────┐
│  PulseServer (server/lib/server.dart): 握手、认证、限速、频道/消息/语音转发、管理    │
│  Store (server/lib/store.dart): data/*.json 原子写 + messages/<id>.log 追加日志       │
│  Passwords (server/lib/passwords.dart): Argon2id（独立 isolate）                      │
└───────────────────────────────────────────────────────────────────────────────────────┘
shared/ (pulse_shared): protocol.dart 帧格式/消息类型/校验；secure.dart 加密通道
```

- **服务端只做转发和持久化**：语音是已编码 Opus 包，服务端不解码、不混音（SFU 式），CPU 占用极低。
- **一个 TCP 长连接**承载 JSON 消息和语音（与 Aurora 相同，便于内网穿透）。语音包 20 ms 一个，TCP_NODELAY；客户端用抖动缓冲吸收波动。
- 降噪、变声完全在发送方本机完成，服务器和其他人只收到处理后的声音。

## 2. 线协议（shared/lib/src/protocol.dart）

帧：`[u32 BE 长度][u8 kind][payload]`，长度含 kind 字节，上限 256 KiB。`kind 0` = UTF-8 JSON，`kind 1` = 语音。

握手后的每个 payload = `counter(8B BE) || ciphertext || tag(16B)`，kind 字节作为 AEAD 附加数据。

语音 payload（解密后）：
- 客户端 → 服务端：`[u16 seq BE][opus 包]`
- 服务端 → 客户端：`[u32 说话人 user id BE][u16 seq][opus 包]`

JSON 消息类型全部定义在 `Msg` 类中（带注释）。流程：
1. 握手（明文 `chello`/`shello`，见 §3）。
2. `register` / `login` / `resume(token)` → `auth_ok {token?, me}` + `welcome {server, channels, members, voice}`；失败 `auth_err {msg, code}`。
3. 之后：`send/edit/delete/react/history/typing`、`vjoin/vleave/vstate`、`profile/chpass`、管理类 `ch_* / set_role / kick / ban / smute / vmove / settings / invite / bans`。服务端广播 `msg / msg_edit / msg_del / reaction / channels / member / presence / vuser / server` 等。

**协议版本** `kProtocolVersion`（登录请求里的 `ver`）。改动不兼容时 +1，服务端会拒绝旧客户端并提示更新。

## 3. 安全设计（参考 Aurora）

| 威胁 | 措施 | 代码 |
|---|---|---|
| 窃听 / 篡改 / 重放 | X25519（临时+服务器长期密钥）→ HKDF-SHA256 → 双向 ChaCha20-Poly1305，64 位递增计数器做 nonce，乱序/重放/篡改立即断开 | `shared/lib/src/secure.dart`（HKDF info `pulse-v1`）|
| 冒充服务器（MITM） | 服务器长期身份 `server_identity.key`；客户端首次连接按地址钉扎公钥（TOFU，类 SSH），之后变化则拒绝连接、显示新指纹，需用户核对后“信任新身份”，且**不会把旧令牌发给新身份** | `AppState.connectTo / trustNewIdentity` |
| 密码泄露 | Argon2id（m=19 MiB, t=2, p=1，OWASP 最低推荐），编码含参数以便日后加强（`needsRehash` 登录时自动升级）；在独立 isolate 计算、并发上限 4 | `server/lib/passwords.dart` |
| 用户名枚举 / 计时攻击 | 不存在的用户也做一次 Argon2id（dummy hash），统一错误信息，失败后随机延迟 | `_preAuth` |
| 暴力破解 | 每 IP+用户名 5 次失败锁定 5 分钟；每 IP 认证 20 次/分钟；每 IP 注册 3 次/小时；常量时间比较 | `server.dart` 常量区 |
| 会话令牌泄露 | 服务器只存 SHA-256(token)；30 天未用过期；每用户最多 20 个会话；改密码会注销其他设备；客户端令牌用 **Windows DPAPI**（当前用户）加密保存，DPAPI 不可用时不保存 | `Store.tokenHash`, `Settings.setToken`, `pn_protect` |
| 滥用 / DoS | 单 IP 连接 12、未认证 4；握手 10 s、认证 3 min 超时；60 s 无心跳断开；JSON 20 条/秒、聊天 1 条/秒（突发 6）、输入提示、语音字节令牌桶；帧/消息/频道名/主题长度上限；用户数、频道数上限 | `Conn` 令牌桶 |
| 文本伪装 | 过滤控制字符、Unicode 方向控制符、零宽字符（昵称完全禁止，消息剥离） | `sanitizeText / hasIllegalChars` |
| 权限 | 服主 > 管理员 > 成员；只能管理角色比自己低的人；服务器密码只有服主能改；所有权限在服务端检查 | `_canModerate`, `_adminDispatch` |
| 钓鱼链接 | 点击链接先弹窗显示真实地址 | `chat_view.dart _openLink` |
| 隐私 | 降噪 / 变声本地完成；服务端不解码语音；诊断日志 `%APPDATA%\Pulse\pulse.log` 只记连接事件，不记消息内容 | |

**注意**：这是“客户端 ↔ 服务器”加密，服务器能看到文字消息（需要存储历史）。如需端到端加密是另一套设计（每频道群组密钥），目前未实现。

## 4. 服务端（server/）

- `bin/pulse_server.exe`：参数、`pulse_server.json`（端口）、身份密钥、控制台命令。
- `lib/server.dart`：`PulseServer`。连接状态机：明文握手 → 加密 → `_preAuth`（异步 Argon2id）→ `_dispatch`。语音只转发给**同一语音频道、未闭麦**的其他人；自己静音 / 被服务器静音时丢弃。
- `lib/store.dart`：
  - `data/users.json`、`sessions.json`、`channels.json`（含服务器名称/公告/注册方式/服务器密码哈希）、`moderation.json`：tmp+rename 原子写，2 秒防抖。
  - `data/messages/<频道id>.log`：每行一个 op（`m` 新消息 / `e` 编辑 / `d` 删除 / `r` 回应），启动时重放；内存只保留每频道最近 5000 条；日志远大于有效消息时自动压缩。
- 测试：`server/test/server_test.dart`（真实 TCP + 加密客户端）。

## 5. 客户端（client/）

### 5.1 Flutter 层
- `lib/main.dart`：加载 `Native` → `Settings` → `AppState`，根据登录状态显示 `ConnectScreen` / `MainScreen`。
- `lib/state/app_state.dart`：唯一业务状态。连接 / 自动重连（指数退避，重连后自动回到原语音频道）、消息（乐观本地回显用 `nonce` 去重）、语音状态、快捷键事件、变声状态、电平轮询（60 ms）。
- `lib/state/settings.dart`：所有偏好；`%APPDATA%\Pulse\settings.json`。
- `lib/native/native.dart`：dart:ffi 绑定。**DLL 缺失时所有调用是空操作**（测试环境就是这样运行的）。事件经 `NativeCallable.listener` 从任意原生线程投递到 Dart 主 isolate；事件 data 由原生 `malloc`，Dart 侧拷贝后 `pn_free`。
- 主题：`lib/theme/themes.dart`，每个主题是一组布局颜色（rail / sidebar / chat / input / hover / accent / text / muted / divider / 在线状态色）；**新增主题只需在 `pulseThemes` 里加一项**。界面所有颜色都通过 `PulseColors.of(context)` 读取。
- 单实例：`windows/runner/main.cpp` 用命名互斥体，第二次启动只激活已有窗口（全局快捷键 / 音频设备只能有一个客户端占用）。

### 5.2 原生引擎 pulse_native.dll（client/native）
C ABI 定义在 `include/pulse_native.h`（**改签名必须 +1 `PN_ABI_VERSION`，并同步 `Native.abiVersion`**）。

采集链（DSP 线程，10 ms 一帧 = 480 样本 @48 kHz 单声道 float）：
```
WASAPI(miniaudio) → 环形缓冲 → 增益 → 80 Hz 高通 → RNNoise(降噪 + 语音概率)
  → 变声(DSP 变调/机器人 | AI；模式切换 30 ms 等功率交叉淡化) → 门限(VAD 滞后 300 ms | 按键说话+释放延迟 | 常开) → 静音
  → 20 ms Opus(VOIP, 复杂度 9, 带内 FEC, 5% 丢包) → PN_EV_PACKET → Dart → 服务器
```
- 降噪 4 档：0 关；1 轻度（60% 湿声）；2 标准；3 强力（再按语音概率衰减残余噪声）。
- VAD 用 RNNoise 的语音概率（平滑后 > 灵敏度阈值）；AI 变声时额外用转换后电平并加长滞后（AI 有延迟）。
- 播放：每个说话人一个 `Speaker`（Opus 解码器 + 按 seq 排序的待播包）。目标缓冲 2–10 包随到达抖动自适应；丢包先用下一包 FEC，否则 PLC；长时间缺包重同步；最后乘每人音量、混音、软削波、乘总音量。监听（麦克风测试）和提示音也混在这里。
- 设备：`pn_list_devices` 返回 WASAPI 设备 id（宽字符串转 UTF-8）；选择的设备打不开会回退到默认；设备被拔出时发 `PN_EV_DEVICE stopped`，Dart 侧 0.5 s 后重启（默认设备会跟随系统）。
- 变声模式切换（`processFrame` 第 3 步）：每帧把干声分别渲染进“当前模式”和“上一模式”，切换后 3 帧做等功率交叉淡化，开关不爆音不断音。AI 模式下若 AI 输出还没准备好（刚加载 / 卡顿 / 热切换），用 40 ms 淡入淡出回退到干声，而不是输出静音。离开 AI 模式后 30 s 内仍把麦克风喂给 AI 并丢弃其输出（保持“热”），所以切回 AI 是即时的；超过 30 s 再切回会先清空历史（`requestReset`），避免播出旧声音。
- 说话者浮窗（`src/overlay.*`）：独立 UI 线程上的分层窗口（`WS_EX_LAYERED | TOPMOST | TOOLWINDOW | NOACTIVATE`，GDI+ 逐像素 alpha 绘制），Pulse 最小化 / 在托盘时也显示。名单（频道名、成员、静音/闭麦/禁言标志、头像图片）由 Dart 推送（`pn_overlay_roster_*`、`pn_overlay_avatar`），**说话高亮直接读音频引擎**（`userSpeakingLevel`：远端为播放电平 + 250 ms 内收到过包，自己为发送门限状态），20 fps 刷新、内容不变时跳过重绘。整窗可拖动（`HTCAPTION`），位置存 `HKCU\Software\Pulse\Overlay`（启动时检查仍在某个显示器上）；× 关闭后发 `PN_EV_OVERLAY`，Dart 把 `settings.overlay` 设为 false。锁定 = `WS_EX_TRANSPARENT` 鼠标穿透。每 2 s 重新声明 TOPMOST（游戏可能把它压下去）。独占全屏的游戏会盖住所有桌面窗口（包括它），无边框 / 窗口化游戏没问题。
- 全局快捷键：独立线程装低级键盘 / 鼠标钩子，**只观察不拦截**（按键照常传给游戏）。修饰键按“至少包含”匹配；`pn_hotkey_capture` 让下一次按键用于绑定（Esc 取消）。以管理员权限运行的游戏需要 Pulse 也以管理员运行（UIPI 限制）。
- 第三方：`third_party/miniaudio`（单头文件，来自 flutter_soloud 包内 v0.11.25）、`third_party/rnnoise`（xiph 官方源码 + 模型数据 `rnnoise_data.c`，SSE4.1/AVX2 运行时分派）、`third_party/onnxruntime/include`（头文件 1.24.4，只用 C API）。`bin/`：`opus.dll`（nuget libopus 1.6.1）、`onnxruntime.dll` + `onnxruntime_providers_shared.dll`（nuget Microsoft.ML.OnnxRuntime.DirectML 1.24.4）、`DirectML.dll`（nuget Microsoft.AI.DirectML 1.15.4）。Opus 和 ONNX Runtime 都是**运行时 LoadLibrary**，缺失时引擎照常工作（无 AI 变声 / 无语音编码会提示）。
- 构建：Flutter runner 的 `windows/CMakeLists.txt` `add_subdirectory(../native)`，install 步骤把 DLL 和 `models/*.onnx` 复制到 `ai\models`，并创建 `ai\providers`、`ai\voices`。单独构建：`cmake -S client/native -B _build/native -G Ninja`（需 VS 开发者环境）。Debug 构建会去掉 `/RTC1`（与 `/O2` 冲突，音频代码始终优化）。

## 6. GPU AI 变声（client/native/src/vc_ai.*）—— 维护重点

### 6.1 流水线
```
48 kHz 处理后人声 ─► 重采样 16 kHz ─► 历史窗口 2 s
每个 block（默认 200 ms）：
  HuBERT(16k 2 s, 固定 [1,32000]) → 768 维特征 50 fps → 复制成 100 fps → 取最后 T 帧
  RMVPE(最后 1.28 s 的 128 维 log-mel, 固定 [1,128,128]) → 360 bin 显著性 → 加权解码 f0 → ×2^(音调/12)
  RVC 生成器(feats, p_len, 粗音高 1–255, f0, sid, rnd) → 模型采样率音频（基础模型 40 kHz，400 样本/帧）
  取 [T-margin-block-fade, T-margin) 段 → 按输入每 10 ms 能量做包络跟随（静音时门控）→ 与上一块尾部 40 ms 余弦交叉淡化
  → 重采样回 48 kHz → 输出环形缓冲 → DSP 线程按帧取出
```
- T = (上下文 + block + fade)/10 + 2，**所有动态维度用 `AddFreeDimensionOverrideByName` 固定为 T**：DirectML 对固定形状编译一次最优图，动态形状会慢一个数量级（实测 RTX 5090：固定 ~20 ms/块，动态 ~100 ms）。
- 推理在独立工作线程（高优先级）；DSP 线程只做 push/pull，不阻塞音频。新形状第一次运行前先在静音上预热（DirectML 要编译内核）。
- **重新配置 / 热切换**（`loaderLoop` / `build`）：单个常驻加载线程，请求先去抖 150 ms 再只执行最新一个（拖动滑块不会排队加载）。运行中切换时，新管线在后台构建，旧管线继续出声，构建完成后在锁内一次性替换 `impl_`（保留 16 kHz 历史，只重置交叉淡化尾巴），没有静音间隙；构建失败则保留旧管线并报告错误。状态 JSON 的 `switching: true` 表示正在后台切换。
- **会话缓存**：HuBERT / RMVPE 形状固定，每个 provider 只建一次；生成器按 (provider, 模型文件, T) 缓存，LRU 保留 5 个（每个约 100–300 MB 显存）。`pn_vc_ai_prewarm` 给出的延迟预设（客户端三个：100/300、200/300、300/500 ms）在空闲时后台预编译，显存 ≥ 6 GB 的显卡才做（`kPrewarmMinVramMB`）。`pn_vc_ai_unload` 清空缓存释放显存。实测 RTX 5090：首次加载 ~3.5 s；预设之间切换 0.15–0.2 s；新的自定义形状 ~1.5 s（期间旧设置继续工作）。
- 客户端在关闭 AI 变声后按 `settings.vcKeepLoadedMin`（默认 10 分钟，0 = 立即，-1 = 永不）才调用 unload，所以随手开关不用重新加载。
- 状态 JSON（`pn_vc_status` / `PN_EV_VC_STATUS`）：state、provider、latencyMs、inferMs、underruns、blockMs、extraMs、switching、error。
- 实测（2026-10，RTX 5090，驱动 32.0.16.1692）：单块推理 18–24 ms，总延迟 ~330–360 ms，`+12` 半音后基频 192→386 Hz。Intel UHD 770 核显：~880 ms/块（跑不动实时，界面会显示卡顿计数）。

### 6.2 推理后端（多厂商）
`pn_gpu_info` 列出显卡和可用 provider id；用户在“变声器 → 计算设备”里选择，保存在 `settings.vcProvider`。

| id | 后端 | 适用 |
|---|---|---|
| `auto` | 显存最大的 D3D12 硬件适配器上的 DirectML | 默认 |
| `dml:<n>` | DirectML，`n` = DXGI `EnumAdapters1` 下标（**就是 DirectML 的 device_id**）| NVIDIA / AMD / Intel / 高通 / 摩尔线程… 任何 DX12 GPU |
| `cuda:<n>` | ORT CUDA EP（仅当 onnxruntime.dll 本身含 CUDA EP 时出现）| NVIDIA，需要 GPU 版 ORT + CUDA/cuDNN DLL |
| `ep:<EP名>:<n>` | **ORT 插件执行提供程序**（`ai\providers\*.dll` 启动时自动 `RegisterExecutionProviderLibrary`），经 `GetEpDevices` 枚举 | 厂商插件：如 NVIDIA TensorRT-RTX、Intel OpenVINO、高通 QNN、AMD 等 |
| `cpu` | ORT CPU | 仅测试 |

显卡枚举：DXGI，按 (VendorId, DeviceId, SubSysId, Revision, 显存) 去重——虚拟显示驱动（模拟器、远程桌面 IddCx）会把同一块物理卡再报一次；两块一模一样的物理卡也会被合并成一个（取第一个下标），如需区分改 `enumerateAdapters` 用 LUID + PCI 位置。厂商名表在 `vendorName()`，新厂商加一行即可。

### 6.3 适配新显卡 / 新驱动 / 新 ORT 版本（操作手册）

**新显卡或新驱动通常什么都不用改**：DirectML 走 D3D12 驱动，任何支持 DX12（特性级 11_0+）的新卡/新驱动都会自动出现在列表里。只有以下情况需要动手：

1. **升级 ONNX Runtime / DirectML**（新显卡架构的 DirectML 优化、性能修复）
   - 从 nuget 下载 `Microsoft.ML.OnnxRuntime.DirectML` 与 `Microsoft.AI.DirectML` 新版（`https://api.nuget.org/v3-flatcontainer/<id小写>/<版本>/<id小写>.<版本>.nupkg`，nupkg 是 zip）。
   - 替换 `client/native/bin/onnxruntime.dll`、`onnxruntime_providers_shared.dll`（`runtimes/win-x64/native/`）和 `DirectML.dll`（`bin/x64-win/`）。
   - 替换 `client/native/third_party/onnxruntime/include/*.h`（`build/native/include/`）。新头文件的 `ORT_API_VERSION` 变大没关系：代码用 `GetApi(ORT_API_VERSION)` 请求编译时的版本；**DLL 必须 ≥ 头文件版本**，否则状态里会显示 “onnxruntime x 比构建版本旧”。
   - 只用到稳定的 C API 函数（列表见 `vc_ai.cpp` 中 `api->` 调用），一般直接能编；若某函数被标记弃用，看 `onnxruntime_c_api.h` 的替代项。
   - 用 `python tools/native_test.py dml:<n>` 回归（需先构建 `_build/native` 或客户端 Release 并把模型放在 `ai\models`）：检查 `AI: ... RTF`（<0.5 才实时）和音高结果。
   - 同时更新 `client/native/third_party/licenses/` 和本文 §5.2 的版本号。
   - 注意 **不要依赖 System32 里的 onnxruntime.dll**（Windows ML 自带的旧版）：引擎按完整路径加载 exe 目录下的那份，并用 `LOAD_WITH_ALTERED_SEARCH_PATH` 让 DirectML.dll 也从同目录解析。

2. **使用厂商专用加速（TensorRT-RTX、OpenVINO、QNN 等）**
   - 首选“插件 EP”方式：把厂商提供的、与当前 ORT 版本匹配的插件 DLL（及其依赖）放进安装目录 `ai\providers\`。启动时自动注册，`pn_gpu_info` 会多出 `ep:<名字>:<n>` 选项，无需改代码。
   - 若厂商只提供“内置 EP 的整套 onnxruntime.dll”（如 CUDA/TensorRT 版 ORT）：直接替换 `onnxruntime.dll` 等，`GetAvailableProviders` 含 `CUDAExecutionProvider` 时列表自动出现 `cuda:<n>`。其他内置 EP（如 `OpenVINOExecutionProvider`、`QNNExecutionProvider`）需要在 `createSession()` 里仿照 CUDA 分支加一个 `SessionOptionsAppendExecutionProvider(so, "<EP 名>", keys, values, n)`，并在 `gpuInfoJson()` 里加 provider 条目。
   - EP 选项（如 TensorRT 引擎缓存路径 `trt_engine_cache_path` 指向 `%LOCALAPPDATA%\Pulse\trt`）通过 `SessionOptionsAppendExecutionProvider_V2` 的 key/value 传入。

3. **新显卡在 DirectML 上出错 / 很慢**
   - 先看“变声器 → 状态”里的错误文字（来自 ORT），以及 `%APPDATA%\Pulse\pulse.log`。
   - 常见对策：更新显卡驱动；更新 ORT+DirectML（上面第 1 条）；在 `createSession()` 的 DML 分支把图优化级别降到 `ORT_ENABLE_BASIC` 试试；或改用 `SessionOptionsAppendExecutionProvider_DML2`（`OrtDmlDeviceOptions{HighPerformance, Gpu}`）让 DirectML 自己挑卡。
   - 显存不足（低端卡）：调大 block（推理次数少）或减小上下文；或改用 fp16 模型（`featsHalf` 已支持 fp16 输入/输出，HuBERT/RMVPE 也可另行转换 fp16）。

4. **新增 / 更换 AI 模型**
   - 生成器要求：RVC v2、768 维 HuBERT 第 12 层特征、带 f0；输入名 `feats/p_len/pitch/pitchf/sid`（`rnd` 可选，存在则传固定高斯噪声）；输出第一个张量为音频；metadata `samplingRate`（必须是 100 的倍数）、`embChannels`、`f0`、`speakers`。加载时会检查并给出清楚的错误。
   - 模型采样率任意（32k/40k/48k 都行，`upp = rate/100`），输出自动重采样到 48 kHz。
   - 其他架构（如 256 维 v1、Beatrice、DDSP）需要在 `AiVoice::step()` 里加分支，并保持“固定形状 + 工作线程 + 交叉淡化”这套结构。

### 6.4 模型文件与下载
三个 ONNX（约 800 MB）不进 git，见 `client/native/models/MODELS.md`（来源、许可、SHA256、I/O）。本机网络 **huggingface.co / github.com 不可达**，用 `https://hf-mirror.com`（路径与 HF 相同）、nuget、`pypi` 阿里云镜像；xiph 资源 `downloads.xiph.org` 会重定向到不可达的 osuosl，RNNoise 源码改从 `gitlab.xiph.org`，模型数据从 `media.xiph.org`（大文件需要断点续传 `curl -C -` 并校验 SHA256）。下载不了时可请用户手动下载后放到对应目录。

基础生成器由 `tools/model_export/export_rvc_base.py` 生成（需要 `torch`、`onnx`，以及同目录 `infer_pack/`——来自 HF 仓库 `lj1995/VoiceConversionWebUI` 的 v1 代码，脚本里补上了 v2 的 768 维文本编码器、说话人条件 NSF 声码器，并把 SineGen 改写成 ONNX 友好的版本）。

## 7. 常见修改指引

| 想做的事 | 改哪里 |
|---|---|
| 新消息类型 | `shared/protocol.dart` `Msg` → `server.dart` `_dispatch`/`_adminDispatch` → `app_state.dart` `_onMessage` |
| 新主题 | `client/lib/theme/themes.dart` `pulseThemes` 加一项 |
| 新设置项 | `settings.dart`（字段 + `_fromJson` + `toJson`）→ `settings_screen.dart` → 需要原生时加 `pn_set_*`（记得 ABI 版本）|
| 新快捷键动作 | `pulse_native.h` 槽位枚举 + `PN_HK_COUNT` → `native.dart HotkeySlot` → `AppState._onNative` → 设置页 |
| 改语音编码参数 | `engine.cpp ensureEncoder()`（复杂度/FEC/码率），服务端 `Conn.voice` 令牌桶要能容纳最高码率 |
| 调降噪 | `engine.cpp processFrame()` 第 2 步；RNNoise 模型更新：替换 `third_party/rnnoise/src/rnnoise_data.c/.h`（与源码版本配套）|
| 服务端限额 | `server.dart` 顶部常量、`Conn` 的 `Bucket` |
| 改说话者浮窗外观 | `client/native/src/overlay.cpp` `render()`（尺寸以 96 DPI 为基准 × DPI × 用户缩放）；名单字段在 `AppState._syncOverlay` |
| 头像规则 | 大小 / 格式 / 尺寸校验在 `shared/protocol.dart validateAvatar`（服务端和客户端共用）；客户端裁剪编码 `client/lib/state/avatars.dart prepareAvatar` |

## 7.1 便利功能速查（实现位置）

| 功能 | 客户端 | 服务端 / 协议 |
|---|---|---|
| 图片头像 | `widgets/avatar_editor.dart`（选择 / 拖入、平移缩放裁剪）、`state/avatars.dart`（256 px PNG/JPEG 编码、按 SHA-256 缓存到 `%APPDATA%\Pulse\avatars`，下载后校验哈希） | `set_avatar` / `get_avatar` / `avatar_data`；`data/avatars/<sha256>.img` 内容寻址，无人引用时删除；上传 30 s/次限速，下载令牌桶 |
| 自定义状态 | 设置 → 我的账号；成员列表显示 | `status_text {text, emoji, until}`，到期由 `_sweep` 清除 |
| 搜索 / 置顶 / 跳转 | `screens/search_panels.dart`、`AppState.search / loadPins / jumpToMessage`；跳到未加载的旧消息时整窗替换为该页并标记 `detached`，显示“回到最新” | `search`（最近 5000 条/频道内子串 + 作者过滤，最多 50 条）、`pin` / `pins`（每频道 ≤ 50）、`around`（以某条为中心的一页） |
| 草稿、新消息按钮、Ctrl+K、Alt+↑↓、Shift+Esc | `screens/chat_view.dart`、`widgets/quick_switcher.dart`、`screens/main_screen.dart` Shortcuts | — |
| 托盘、关闭到托盘、窗口位置 | `platform/shell.dart`（tray_manager / window_manager）；`windows/runner/window_state.h`（`HKCU\Software\Pulse\WindowPlacement`） | — |
| @提及任务栏闪烁、静音说话提醒 | `pn_flash_window`；`PN_EV_MUTED_TALK`（3 s 一次） | — |

## 8. 测试与验证记录

- `server`: `dart test` — 10 项（认证、锁定、消息权限、持久化、语音转发规则、邀请/封禁、篡改、重放、头像上传/伪造文件拒绝/路径穿越、状态/搜索/置顶/跳转）。
- `client`: `flutter test` — 真实 `AppState` ↔ 进程内服务端（聊天、乐观回显、语音加入/静音同步、建频道、服务器身份变更检测、心跳保持连接；头像裁剪→上传→另一客户端下载并校验哈希、搜索、置顶、跳转、状态）。
- 变声切换（`tools/dev/switch_test.py`、`toggle_test.py`，RTX 5090）：预设切换 0.15–0.2 s，期间不中断；25 次快速切换 关/经典/AI 无爆音（最大样本跳变 0.04）、无额外断音（AI 段的“静音帧”与一直开 AI 时相同，是 AI 自身 ~0.35 s 延迟）。
- 说话者浮窗（GUI + 机器人实测）：机器人说话时高亮、拖动后位置写入注册表、× 关闭后设置同步、语音面板按钮重新打开、离开语音自动隐藏 / 重新加入自动显示、主窗口关到托盘后浮窗仍显示；锁定后为鼠标穿透（`tools/dev/overlay_lock_test.py`）。
- 原生（`tools/native_test.py`、VB-Cable 回环）：降噪“语音/静音段能量比” 关 4 dB → 标准 34 dB；DSP 变调 +5 半音 191→245 Hz；AI 变调 +12 半音 192→386 Hz（实时回环 403 Hz）；Opus 包序号连续；全局钩子开关正常。
- GUI：两个客户端（GUI + 协议机器人）同时在线，文字消息 / @提醒 / 未读角标、语音互通与说话指示、全局快捷键捕获（F8）均已手动验证。
