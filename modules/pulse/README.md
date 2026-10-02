# Pulse

类似 Discord 的 Windows 文字 / 语音聊天工具：**独立服务端 + Windows 客户端**，全部通信加密。

- 文字聊天：多个文字频道、历史记录（服务端持久化）、编辑 / 删除 / 回复 / 表情回应、@提及提醒、正在输入提示、链接（打开前确认）、`代码`、**加粗**。
- 语音聊天：多个语音频道、Opus 编码（最高 128 kbps，带 FEC / 丢包隐藏）、自适应抖动缓冲、说话指示、每人单独音量 / 本地静音。
- **全局快捷键**：按键说话（开麦键）、切换静音、切换闭麦、切换变声器；后台 / 全屏游戏中依然有效，支持鼠标中键 / 侧键。
- **实时降噪**：RNNoise 神经网络降噪（4 档），同时提供语音激活检测。
- **变声器**：经典变声（变调 / 机器人，零延迟）和 **AI 变声（用本机显卡运行 RVC 模型）**；支持 NVIDIA / AMD / Intel / 高通等任意 DirectX 12 显卡（DirectML），可扩展 CUDA 和厂商 ONNX Runtime 插件。
- **输入 / 输出设备选择**、输入音量（增益）、输出音量、麦克风测试（回放自己处理后的声音）、提示音音量。
- **17 款主题** + 自定义强调色 + 界面缩放。
- 管理：首个注册用户为服主；管理员可建 / 改 / 删 / 排序频道、慢速模式、语音码率、踢出 / 封禁 / 服务器静音 / 移动成员、邀请码、注册方式、服务器密码。
- **说话者浮窗**：在语音频道时显示一个置顶小窗（Pulse 最小化 / 在托盘里也在），列出频道成员并实时高亮正在说话的人、显示静音 / 闭麦；可拖动（位置记忆）、点 × 关闭、语音面板按钮或全局快捷键重新打开；可选“只显示正在说话的人”、透明度、大小、锁定为鼠标穿透。
- **便利功能**：图片头像（拖入 / 选择图片，拖动缩放裁剪）、自定义状态（图标 + 文字 + 自动清除）、消息搜索（`from:名字`）、置顶消息、点击回复跳转到原消息、频道草稿、“N 条新消息 / 回到最新”按钮、Ctrl+K 快速切换、Alt+↑↓ 切换频道（加 Shift 只跳未读）、Shift+Esc 全部已读、@提及时任务栏闪烁、静音说话提醒、关闭到托盘（托盘菜单可静音 / 闭麦 / 退出）、记住窗口位置。
- **变声切换无缝**：开关 / 切换模式有 30 ms 交叉淡化、不会爆音或断音；AI 模型关闭后默认保留 10 分钟，再开即用；三个延迟预设在后台预编译，切换几乎即时，切换期间旧设置继续工作。

安全设计参考 Aurora（X25519 + ChaCha20-Poly1305 加密通道、服务器身份钉扎、限速与滥用防护），并加入账号体系（Argon2id 密码哈希、会话令牌 DPAPI 加密保存）。详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 目录

| 目录 | 说明 |
|---|---|
| `server/` | 服务端（Dart 控制台程序，编译为 `pulse_server.exe`） |
| `client/` | Windows 客户端（Flutter），`client/native/` 是 C++ 音频引擎 `pulse_native.dll` |
| `shared/` | 协议、校验、加密通道（服务端与客户端共用） |
| `tools/` | 模型导出脚本、原生引擎测试脚本 |
| `build.ps1` | 一键构建 `dist\`（服务端 exe + 客户端 + zip） |

## 服务端

```
pulse_server.exe                         # 首次运行交互输入端口和名称，保存到 pulse_server.json
pulse_server.exe --port 7800 --name "周末开黑"
pulse_server.exe --data D:\pulse-data    # 自定义数据目录
```

- 默认 TCP 7800；局域网发现 UDP 7801（客户端“搜索局域网服务器”）。内网穿透只需映射 TCP 端口。
- **第一个注册的账号自动成为服主**。
- 数据在 exe 同目录 `data\`（用户、会话、频道、封禁、消息记录），`server_identity.key` 是服务器身份私钥：**请备份、不要外传**；删除后所有客户端会提示“服务器身份已改变”。
- 控制台命令：`users`、`online`、`kick/ban/unban <用户>`、`op/deop/owner <用户>`、`resetpw <用户> <新密码>`、`reg open|invite|closed`、`invite [次数] [小时]`、`storage [days|max|file <数值>]`、`say <公告>`、`quit`。
- **文件 / 图片附件**：数据在 `data\files\`。默认保留 **7 天**后自动删除；总存储超过上限（默认 20 GB）时先删除最旧的文件；单个文件最大 **2 GB**（可调低）。在客户端「服务器菜单 → 文件存储」或控制台 `storage` 命令设置。
- **角色与权限**：类似 Discord，可创建多个角色、按频道允许 / 拒绝权限（私密频道、只读频道等）。旧版的“管理员”账号升级后自动归入「管理员」角色。
- **私信**：成员之间一对一私聊，只有双方可见。
- **屏幕共享**：在语音频道中共享屏幕或窗口（H.264，优先使用显卡硬件编码），由服务器转发给点击观看的人。
- 本版协议版本为 2，**服务端和客户端需同时更新**。

## 客户端

运行 `pulse.exe` → 输入 `服务器地址:端口`（或搜索局域网）→ 核对服务器指纹 → 注册 / 登录。之后会自动登录（令牌经 DPAPI 加密保存在 `%APPDATA%\Pulse\settings.json`）。

- 设置（Ctrl+,）：我的账号（头像、自定义状态）/ 语音与音频（含说话者浮窗）/ 变声器（GPU）/ 快捷键 / 外观与主题 / 通知 / 关于。
- 键盘：Ctrl+K 快速切换、Ctrl+F 搜索、Alt+↑↓ 切换频道、↑ 编辑上一条消息、Esc 取消回复 / 编辑、Shift+Esc 全部已读。
- 语音面板：断开、按住说话按钮、变声器状态与延迟。
- 右键频道 / 成员 / 消息有更多操作。
- 自定义 AI 音色：把 RVC v2（768 维、带音高）ONNX 模型放进安装目录 `ai\voices\`，在“变声器”页选择。

## 构建

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1        # 测试 + 构建 → dist\
powershell -ExecutionPolicy Bypass -File build.ps1 -SkipTests
```

需要 Flutter（本机 `D:\Tools\flutter`）和 Visual Studio C++ 工具链。AI 模型（约 800 MB）不在 git 中，放在 `client/native/models/`，来源见 `client/native/models/MODELS.md`。

## 测试

```
cd server && dart test          # 注册/登录/锁定、消息增删改/回应/权限、持久化、语音转发规则、邀请/封禁、篡改/重放断开
cd client && flutter test       # 真实客户端状态机 ↔ 真实服务端：聊天、语音加入/静音、建频道、服务器身份变更检测、心跳
tools\dev\nb.bat                     # 单独构建 pulse_native.dll 到 _build\native（下面的原生测试用）
python tools/native_test.py dml:0   # 原生引擎：设备、显卡枚举、降噪对比、经典变声、AI 变声
python tools/dev/switch_test.py dml:0   # AI 变声重配置 / 开关耗时
python tools/dev/toggle_test.py dml:0   # 快速切换变声模式：不爆音、不断音
python tools/dev/overlay_test.py        # 说话者浮窗截图（_build\overlay.png）
python tools/dev/bot.py 127.0.0.1:7800 10   # 协议机器人：加入语音并“说话”，用于手动测试
```

## 第三方组件

Flutter、Opus（BSD）、RNNoise（BSD）、miniaudio（MIT-0 / 公有领域）、ONNX Runtime 与 DirectML（MIT，许可证见客户端 `licenses\`）、RVC / RMVPE / HuBERT 预训练模型（MIT，lj1995/VoiceConversionWebUI）。
