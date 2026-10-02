# Aurora 游戏开发指南（给每个游戏包的实现者）

项目结构：
- `shared/` 纯 Dart 包 `aurora_shared`：协议 + **所有游戏引擎**（服务端权威运行）。不能 import Flutter。
- `server/` Dart 控制台服务端（TCP），运行 `shared` 里的引擎。
- `client/` Flutter 客户端（Windows/Android/macOS/iOS），为每个游戏提供棋盘/牌桌 UI。

Flutter SDK: `D:/Tools/flutter/bin/flutter`，Dart: `D:/Tools/flutter/bin/dart`。

## 你负责的文件（只改这些，不要动别的包，否则会和并行开发的同事冲突）
- `shared/lib/games/<pkg>/**` —— 引擎。`defs.dart` 导出 `final List<GameDef> <pkg>Games`。
- `client/lib/games/<pkg>/**` —— UI。`boards.dart` 导出 `final Map<String, BoardBuilder> <pkg>Boards`（key = GameDef.id）。
- 可以在 `shared/test/<pkg>_test.dart` 写测试。
- **不要修改** `shared/lib/src/*`、`shared/lib/registry.dart`、`client/lib/widgets/*`、`client/lib/games/boards.dart`、`server/*`。
  如确实需要公共能力，在自己包里写一个私有 helper。

## 引擎契约（`shared/lib/src/engine.dart`）
```dart
class MyGame extends GameEngine {
  MyGame(super.setup);                 // setup.players, setup.options, setup.names, setup.bots, setup.hostSeat, rng
  void start();                        // 发牌/初始化，可用 host.log('...') 往聊天框写系统消息
  void handle(int seat, Map<String, dynamic> a); // 非法操作 throw GameError('中文提示')
  Map<String, dynamic> view(int seat); // seat=-1 为观众；只能包含该座位可见的信息（别人的手牌要隐藏！）
  List<int> get waitingFor;            // 当前等待哪些座位操作（同时行动的游戏可返回多个）
  bool get isOver;
  Map<String, dynamic>? bot(int seat); // 电脑玩家：返回一个**合法**操作；尽量有基本策略
  int get botDelayMs => 800;
}
```
- view 只能包含 JSON 类型（Map<String,dynamic>/List/String/num/bool/null），**Map 的 key 必须是 String**。
- 服务端在每次 handle() 成功后给所有人推送 view。
- 定时：`host.schedule(ms, () {...})` 例如回合结算展示 3 秒后进入下一局。回调执行后服务端自动推送。
  simulator 会立即执行 schedule 的回调，所以 **不要依赖定时器来推进必须的流程之外的东西**；
  等待期间 waitingFor 应返回 `[]`。
- 玩家掉线/离开时服务端会让 bot() 代打，所以 bot() 必须在任何 waitingFor 状态下都能给出合法操作。
- 同一 seat 可能在 waitingFor 中但 bot 返回 null → simulator 会报 stuck。不要这样。
- 多局制游戏（麻将半庄、斗地主多局等）：整场结束才 isOver=true；局间用 schedule 或让玩家点“继续”（waitingFor 包含所有需点继续的人，bot 自动点）。
- 用 `rng`（setup.rng）做所有随机，保证可复现。
- 有 GM/出题人这类非对称角色时，用 `setup.hostSeat` 或选项决定。

## GameDef（写在你的 defs.dart）
```dart
GameDef(
  id: 'doudizhu',                 // 全局唯一、小写
  name: '斗地主',
  category: '牌类',              // 只能用：麻将 / 棋类 / 牌类 / 桌游 / 派对
  description: '一句话规则简介',
  playerRange: (opts) => (3, 3),   // 可随选项变化
  options: [OptionDef('decks', '牌数', [OptionChoice(1, '一副牌'), OptionChoice(2, '两副牌')], 1)],
  create: MyGame.new,
)
```
选项值只用 int / String / bool。同一个游戏的多个变体尽量用一个 GameDef + 选项（例如 UNO 的 经典/FLIP/NO MERCY），
除非变体完全是另一个游戏（例如雀魂各模式可以各自一个 GameDef，也可以是选项，自行决定，推荐各自一个 id 便于大厅展示）。

## 自测（必须做）
1. `cd shared && D:/Tools/flutter/bin/dart run tool/simulate.dart <gameId> 30` —— 所有人数×选项组合全部 bot 对打 30 局必须 ALL OK。
2. `cd shared && D:/Tools/flutter/bin/dart analyze lib/games/<pkg>` 无 error/warning。
3. `cd client && D:/Tools/flutter/bin/flutter analyze lib/games/<pkg>` 无 error/warning。
4. 规则关键部分写单元测试（`shared/test/<pkg>_test.dart`，`dart test test/<pkg>_test.dart`）。

注意：registry 已经引用你的 `<pkg>Games`/`<pkg>Boards`，所以你加完就会出现在大厅里。
其他人也在同时开发别的包，如果 analyze 整个项目出现别人包里的错误，忽略它们，只关心你自己的目录。
simulate.dart 只跑你指定的 gameId，不受别人影响（但若别人包有编译错误会导致无法运行——此时稍等片刻重试，或临时用
`dart run tool/simulate.dart` 之外的方式：在 `shared/test/<pkg>_test.dart` 里直接 import 你自己的 defs.dart 调 `runSims(<pkg>Games)`，
`import 'package:aurora_shared/src/simulate.dart';`）。**推荐直接用测试文件方式，完全隔离。**

## 客户端 UI（`client/lib/games/<pkg>/`）
```dart
import 'package:flutter/material.dart';
import '../../widgets/common.dart';   // GameContext, PlayerTag, StatusBar, ResultBanner, Avatar, BoardBuilder
import '../../widgets/pieces.dart';   // MahjongTile, PlayingCard, OverlapRow, DieFace

class MyBoard extends StatefulWidget { final GameContext g; ... }
```
`GameContext g`：
- `g.view` 当前座位的 view（你的引擎生成的 Map）
- `g.seat` 我的座位（-1 = 观战），`g.players`，`g.name(s)`，`g.avatar(s)`，`g.bot(s)`，`g.over`
- `g.act({...})` 发送操作到服务端 → 引擎 handle(seat, action)
- `g.seatsFromMe()` 以我为起点的座位顺序（用于把自己放在下方）
- `g.tag(s, active: true, sub: '分数 25000')` 玩家头像名牌
- `g.table` 当前主题的桌面颜色
- 错误（GameError）会自动以 SnackBar 提示，不用处理。

UI 要求：
- 自适应：手机竖屏(≈390×800)、手机横屏、Windows 窗口(≈1280×720) 都要可用，不溢出。用 LayoutBuilder / FittedBox / Wrap。
- 棋盘类用 CustomPaint 或 Stack 绘制；尽量美观（阴影、圆角、高亮最后一步、可落点提示）。
- 明确显示：轮到谁、我能做什么、上一步发生了什么、结束时的结果（ResultBanner）。
- 聊天/语音/离开按钮在外层，棋盘只负责游戏区域。
- 颜色用 `Theme.of(context).colorScheme` 和 `g.table`，以适配 36 个主题（亮/暗）。
- 棋盘组件必须是纯函数式地根据 g.view 渲染（本地只存选中状态之类的临时 UI 状态）。

扑克牌编码（PlayingCard）：`'3S'`、`'TH'`(10)、`'AD'`、`'2C'`、`'BJ'` 小王、`'RJ'` 大王。
麻将牌编码（MahjongTile）：`'1m'..'9m'`,`'1p'..'9p'`,`'1s'..'9s'`,`'0m'/'0p'/'0s'`(赤五),`'1z'..'7z'`=东南西北白发中，`'back'`=背面。
MahjongTile(code, width: 36, sideways: true/false, selected, highlight, dim, onTap, badge)。

## 补充（第二批游戏）
- 客户端渲染测试（必须通过）：在 `client` 目录运行
  `powershell -NoProfile -ExecutionPolicy Bypass -File D:/Tools/fbuild.ps1 test test/boards_render_test.dart --plain-name "board renders: <gameId>"`
  它会在 390×800 / 800×390 / 1280×720 三种尺寸下用真实引擎视图（开局、中局、各 phase 变化、结束）渲染棋盘，溢出或异常即失败。
  **必须用 fbuild.ps1 运行**（它修复了本机 PATH 问题），不要直接 `flutter test`。
- 截图自查（强烈建议，看看是否美观）：`$env:SHOTS=1; powershell ... fbuild.ps1 test test/screenshot_test.dart --plain-name <gameId>`，
  图片在 `client/build/shots/<gameId>_desk.png` / `_phone.png`，可以用 Read 工具查看图片。
- CustomPainter 里的 TextStyle 请加 `fontFamilyFallback: kFontFallback`（来自 widgets/common.dart），否则中文/符号会显示成方块。
- 小尺寸卡牌/牌面内的文字用 FittedBox(fit: BoxFit.scaleDown) 包裹，防止溢出。
- 麻将牌用 widgets/pieces.dart 的 MahjongTile（PNG 素材，已含花牌之外的全部 34 种 + 赤五）；花牌（春夏秋冬梅兰竹菊）没有素材，需要自己用 Container+文字绘制。
- 扑克牌用 PlayingCard；UNO/自定义牌自己画。
- 电脑玩家不得读取其座位看不到的隐藏信息（参考 military/junqi_ai.dart 的做法）——除非游戏本身无隐藏信息。

## 第三批：平台新能力（所有游戏包都要接入）

引擎基类（`shared/lib/src/engine.dart`）新增的可选能力，按需 override：

| 成员 | 作用 | 何时实现 |
|---|---|---|
| `List<int>? get placings` | 结束时每个座位的名次（1=最好，并列同名次；团队游戏赢家全 1、输家全 2）。用于 **战绩 / Elo / 系列赛 / 胜负音效** | **所有游戏必须实现**（isOver 后返回非 null，长度 = players）。可用 `rankByScore(scores)`、`rankWinners(players, winners)` |
| `bool get canResign` + `void resign(int seat)` | 认输。两人游戏：对方获胜并 isOver；多人游戏：该座位出局（或整局结束），自己设置 placings | 棋类、两人对战类必须；其他可选 |
| `bool get canDraw` + `void agreeDraw()` | 求和（服务端在所有真人同意后调用） | 棋类 |
| `Set<int>? voiceListeners(int seat)` | 语音路由：此刻谁能听到 seat 说话（null = 所有人）。例：狼人夜晚只有狼人互相听到、死亡玩家不能对活人说话 | 有夜晚/秘密阶段的社交推理游戏 |
| `int get botLevel` | 房主选的电脑难度 0 简单 / 1 普通 / 2 困难 | bot() 应据此调整：简单=常犯错/随机合法步，困难=更强搜索或更好策略 |
| `bool get aiOn` + `setup.ai` | 服务器配置了大模型（`.env`）且房间开启了本游戏的 `ai` 选项 | 互动性强的游戏（见下） |

`GameDef` 新增：
- `rules: '''...'''` —— **完整规则说明**（纯文本；`# 标题` 行、`- ` 列表）。客户端房间里有“规则”按钮。**所有游戏必须写**，300~1500 字，写清流程、计分、特殊牌/棋子、胜负条件、本实现的选项含义。
- `undo: true` —— 支持悔棋。服务端用 **同一个随机种子重建引擎并重放操作日志（去掉被悔的步）**。只有满足以下条件才能设为 true：
  handle() 在同一种子下完全确定（不读时钟、不依赖定时器推进）、bot() 不修改游戏状态、没有隐藏信息被重新洗牌利用的问题（一般只给无随机或随机仅在开局的棋类）。simulator 会自动验证“按日志重建 == 原局面”。

**bot() 里的随机**：`rng` 在 bot() 调用期间自动切换为独立的 bot 随机数（不影响游戏自身随机序列），所以 bot() 里可以放心用 `rng`。但 **bot() 绝对不能修改游戏状态**（记账字段如 `_botTried` 之类如果影响 waitingFor，就不能 `undo: true`）。

**不要用 `DateTime.now()` 推进规则**（显示倒计时可以）。回放是记录视图而不是操作，所以实时/计时游戏的回放不受影响。

### 大模型（AI）接入 —— `shared/lib/src/ai.dart`
服务端在 `.env` 配置 OpenAI 或 Anthropic 后，`setup.ai` 非 null。接入方式：
1. 在 GameDef.options 加 `OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false)`（key 必须叫 `ai`，客户端会在服务器未配置 AI 时提示）。
2. 在 bot() 里：
```dart
final _ai = AiSlot();
Map<String, dynamic>? bot(int seat) {
  if (aiOn) {
    final r = _ai.poll(setup.ai!, 'desc:$round:$seat', () => AiRequest(system: '你在玩谁是卧底…', prompt: '你的词是…'));
    if (r.pending) return null;            // 结果还没回来：返回 null，服务端稍后再问
    final t = r.text;                      // null = 失败/超时
    if (t != null && valid(t)) return {'type': 'describe', 'text': AiText.firstLine(t, maxLen: 40)};
  }
  return heuristic(seat);                  // 永远要有非 AI 的兜底
}
```
3. **只把该座位能看到的信息写进 prompt**（和 bot 规则一样，不能泄露隐藏信息）。
4. 模型回复要严格校验（长度、是否合法、是否直接说出了答案词等），不合格就用兜底。
5. 可以传图：`AiImage.fromStrokes(strokes)` 把画板笔画栅格化成 PNG（你画我猜/传话画画让 AI 看图猜词）。
6. simulator 会用 `FakeAi` 给出各种垃圾/失败/正常回复来测试你的校验与兜底，所以 `ai=true` 的选项组合也必须 ALL OK。
7. `r.pending` 返回 null 时，**waitingFor 里仍包含该座位是允许的**（服务端会定期重试）；但 simulator 中 FakeAi 是同步的，不会 pending。

### 新游戏包（本批）
`mahjong2`（长沙麻将、二人麻将）、`cards4`（够级、保皇、双扣、Gin Rummy）、`abstract2`（Hive 蜂巢、Blokus 格格不入、Onitama 师徒棋、Quarto）、`euro2`（Azul 花砖物语、王国骨牌、拼布艺术、七大奇迹·对决）、`light`（谁是牛头王、No Thanks、寿司狗、政变、心灵同步 The Mind、骷髅与玫瑰）、`party3`（Just One、Wavelength 频率猜心、成语接龙、飞花令）。

### 客户端（不需要各包处理）
音效（轮到我、胜/负、表情）、表情/快捷语、托管、认输/求和/悔棋按钮、规则说明、回放播放器、战绩/排行榜、单机模式、局域网发现 都由平台层实现。
**单机模式**会在客户端本地运行你的引擎（`setup.ai == null`），所以引擎不能依赖 dart:io。
**回放**会用你的 Board 组件渲染历史视图（`g.act` 无效、`g.replay == true`），Board 必须能在 `g.act` 不起作用时正常显示。
