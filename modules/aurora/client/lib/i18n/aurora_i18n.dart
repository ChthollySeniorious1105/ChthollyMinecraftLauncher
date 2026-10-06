import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Languages supported by Aurora's desktop, embedded and web clients.
enum AuroraLanguage {
  zhCN('zh', '简体中文'),
  en('en', 'English');

  final String code;
  final String label;
  const AuroraLanguage(this.code, this.label);

  static AuroraLanguage fromCode(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => zhCN);

  /// Flutter locale. Chinese carries the Hans script so Material picks the Simplified strings
  /// and the text engine prefers Simplified Han glyphs.
  Locale get locale => switch (this) {
    zhCN => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
      countryCode: 'CN',
    ),
    en => const Locale('en'),
  };

  static List<Locale> get locales => [for (final l in values) l.locale];

  /// Material / Cupertino / Widgets strings for every Aurora language. Without these a `zh`
  /// locale has no MaterialLocalizations and every TextField, tooltip and dialog fails to build.
  static const delegates = GlobalMaterialLocalizations.delegates;
}

/// The language used by strings that are created without a BuildContext (for example,
/// connection errors, local-game messages and invite text).
AuroraLanguage currentAuroraLanguage = AuroraLanguage.zhCN;

/// Small, source-keyed translation table. Chinese remains the source language so existing
/// saved replays and server messages continue to work. New UI can use [auroraT] immediately;
/// adding a key here is enough to expose it in both the CML embed and the web client.
const Map<String, String> auroraEnglish = {
  '联机小游戏': 'Online party games',
  '服务器地址或邀请链接': 'Server address or invite link',
  '例如 http://192.168.1.10:7790（网页版端口）':
      'e.g. http://192.168.1.10:7790 (web port)',
  '例如 192.168.1.10:7788': 'e.g. 192.168.1.10:7788',
  '连接中…': 'Connecting…',
  '连接服务器': 'Connect to server',
  '搜索局域网服务器': 'Find LAN servers',
  '正在搜索局域网…': 'Searching the LAN…',
  '没有发现局域网服务器（确认服务器已启动且在同一网络）': 'No LAN servers found (check that the server is running on the same network)',
  '最近连接': 'Recent connections',
  '单机游戏（与电脑对战）': 'Single-player (play against bots)',
  '本机回放': 'Local replays',
  '信任新的服务器身份？': 'Trust the new server identity?',
  '只有在你确认服务器管理员重装/更换过服务器时才这样做。可以请管理员核对服务器控制台显示的"服务器指纹"。': 'Only do this after confirming that the server was reinstalled or replaced. Ask the administrator to compare the server fingerprint shown in the console.',
  '取消': 'Cancel',
  '信任': 'Trust',
  '我确认服务器是可信的，信任新身份':
      'I confirm this server is trusted; trust the new identity',
  '输入房间号': 'Enter room code',
  '输入房间密码': 'Enter room password',
  '房间密码（如有）': 'Room password (if any)',
  '以观战者身份进入': 'Join as a spectator',
  '进入': 'Join',
  '创建房间': 'Create room',
  '还没有房间，创建一个吧！': 'No rooms yet. Create one!',
  '观战': 'Spectate',
  '对局中': 'Playing',
  '等待中': 'Waiting',
  '大厅': 'Lobby',
  '在线 {0}  ': 'Online {0}  ',
  '刷新': 'Refresh',
  '对局回放': 'Replays',
  '战绩与排行': 'Stats & leaderboard',
  '单机游戏': 'Single-player',
  '设置': 'Settings',
  '连接已断开': 'Disconnected',
  '个人资料': 'Profile',
  '昵称': 'Display name',
  '头像': 'Avatar',
  '保存': 'Save',
  '返回': 'Back',
  '主题': 'Theme',
  '语言': 'Language',
  '简体中文': 'Simplified Chinese',
  'English': 'English',
  '音效': 'Sound effects',
  '音量': 'Volume',
  '麦克风': 'Microphone',
  '输入增益': 'Input gain',
  '输出音量': 'Output volume',
  '按住说话': 'Push to talk',
  '重新开始': 'Restart',
  '规则': 'Rules',
  '邀请链接 / 二维码': 'Invite link / QR code',
  '入座': 'Take a seat',
  '准备': 'Ready',
  '取消准备': 'Cancel ready',
  '更换游戏': 'Change game',
  '公开': 'Public',
  '私密': 'Private',
  '私密房间': 'Private room',
  '空位': 'Open seat',
  '添加电脑': 'Add bot',
  '电脑': 'Bot',
  '离线': 'Offline',
  '房主': 'Host',
  '已准备': 'Ready',
  '未准备': 'Not ready',
  '思考时间（超时电脑代打）': 'Turn time (bot plays after timeout)',
  '不限': 'No limit',
  '电脑难度': 'Bot difficulty',
  '服务器未配置 AI，将使用普通电脑':
      'AI is not configured on this server; a standard bot will be used',
  'AI 电脑：': 'AI bot: ',
  '派对之夜': 'Party night',
  '创建派对之夜': 'Create party night',
  '结束派对': 'End party',
  '投票选择下一款游戏（同票按队列顺序）': 'Vote for the next game (queue order breaks ties)',
  '按投票进入下一局': 'Start the next round from the vote',
  '积分榜': 'Scoreboard',
  '换游戏后清零': 'Resets when the game changes',
  '邀请': 'Invite',
  '复制': 'Copy',
  '二维码': 'QR code',
  '聊天': 'Chat',
  '发送': 'Send',
  '请输入消息': 'Type a message',
  '表情': 'Emotes',
  '认输': 'Resign',
  '求和': 'Offer draw',
  '托管': 'Auto-play',
  '观战中': 'Spectating',
  '关闭': 'Close',
  '管理成员': 'Manage members',
  '踢出房间': 'Remove from room',
  '踢出': 'Remove',
  '本房间积分': 'Room points',
  '统计': 'Statistics',
  '总局数': 'Games',
  '胜率': 'Win rate',
  '排行榜': 'Leaderboard',
  '没有战绩': 'No stats yet',
  '来 Aurora 一起玩': 'Join me on Aurora for ',
  '秒后返回房间 · 点击立即返回': ' seconds until the room · tap to return now',
  'AURORA 加载中…': 'Loading AURORA…',
  '分钟': 'min',
  '人': 'players',
  '{0} 人': '{0} players',
  '{0}~{1} 人': '{0}–{1} players',
  '分': 'points',
  '胜': 'wins',
  '局': 'games',
  '第': 'Round ',
  '号位': ' seat',
  '中文提示重排字块，拼出成语或我的世界词语；支持撤回、跳过。': 'Rearrange tiles from a Chinese clue to form an idiom or Minecraft word; undo and skip are supported.',
  '断开连接': 'Disconnect',
  '大厅聊天': 'Lobby chat',
  '例如 A7K2Q': 'e.g. A7K2Q',
  '请输入房间名': 'Enter a room name',
  '房间名': 'Room name',
  '密码（可选）': 'Password (optional)',
  '搜索游戏（名称/简介）': 'Search games (name/description)',
  '帮我选': 'Pick for me',
  '创建': 'Create',
  '返回房间': 'Back to room',
  '离开房间': 'Leave room',
  '离开': 'Leave',
  '结束': 'End',
  '结束对局？': 'End the game?',
  '离开房间？': 'Leave the room?',
  '对局进行中，离开后将由电脑托管你的座位。':
      'The game is in progress. Leaving will let a bot take your seat.',
  '完成': 'Done',
  '音量调节': 'Volume',
  '语音音量调节': 'Voice volume',
  '说点什么…': 'Say something…',
  '笑哭': 'Tears of joy',
  '贴表情': 'Add reaction',
  '复制邀请链接': 'Copy invite link',
  '已连接服务器，点击加入邀请房间': 'Connected to the server. Tap to join the invited room.',
  '请填写有效的 http 或 https 地址': 'Enter a valid http or https address',
  '邀请好友 · 扫码加入': 'Invite friends · scan to join',
  '好友可访问的网页版地址': 'Web address your friends can access',
  '房间密码（没有则留空）': 'Room password (leave blank if none)',
  '加入房间': 'Join room',
  '加入': 'Join',
  '游戏': 'Game',
  '对局记录': 'Game log',
  '暂无记录': 'No records',
  '规则说明': 'Rules',
  '看回放': 'Watch replay',
  '再来一局': 'Play again',
  '开始游戏': 'Start game',
  '退出单机游戏': 'Exit single-player',
  '悔棋': 'Undo',
  '人数（你 + 电脑）': 'Players (you + bots)',
  '随机': 'Random',
  '正在下载回放…': 'Downloading replay…',
  '还没有回放': 'No replays yet',
  '该视角没有记录': 'No recording for this view',
  '观众视角': 'Spectator view',
  '上一步': 'Previous step',
  '下一步': 'Next step',
  '播放速度': 'Playback speed',
  '保存到本机': 'Save locally',
  '复制文件路径': 'Copy file path',
  '删除': 'Delete',
  '暂无上榜玩家（至少完成 3 局才上榜）':
      'No ranked players yet (complete at least 3 games to appear)',
  '服务器未返回玩家身份，暂不记录战绩': 'The server did not return a player identity, so stats are not recorded yet',
  '还没有对局记录（与电脑或好友完成一局后显示）':
      'No game records yet (finish a game with a bot or friend to see them)',
  '主题与设置': 'Themes & settings',
  '界面主题': 'Interface theme',
  '主题跟随 CML 启动器，在 CML「设置 → 外观」中切换。': 'The theme follows the CML launcher. Change it in CML Settings → Appearance.',
  '界面缩放': 'Interface scale',
  '界面字体': 'Interface font',
  '默认（Claude Sans）': 'Default (Claude Sans)',
  '从系统已安装的字体中选择，缺字时自动回退':
      'Choose any installed font; missing characters fall back automatically',
  '恢复默认': 'Reset',
  '选择字体': 'Choose font',
  '搜索字体': 'Search fonts',
  '未能读取系统字体，可使用默认字体':
      'Could not read the system fonts; the default font is available',
  '共 {0} 款系统字体': '{0} system fonts',
  '字体预览 Aurora 123': 'Font preview 字体 Aurora 123',
  '游戏音效': 'Game sounds',
  '轮到我、开局、胜利/失败、表情提示音': 'Your turn, game start, win/loss and emote sounds',
  '音效音量': 'Sound volume',
  '出牌方式': 'Discard method',
  '双击：先点选中，再点同一张打出': 'Double tap: select a tile, then tap it again to discard',
  '单击：点一下直接打出': 'Single tap: tap once to discard',
  '单击': 'Single tap',
  '双击': 'Double tap',
  '语音': 'Voice',
  '降噪强度': 'Noise reduction',
  '关闭降噪': 'Noise reduction off',
  '轻度': 'Light',
  '标准': 'Standard',
  '强力': 'Strong',
  '按键说话': 'Push to talk',
  '开启后需按住房间内的“按住说话”按钮才会发送语音':
      'When enabled, hold the “push to talk” button in the room to send voice',
  '结束当前派对？': 'End this party?',
  '本次派对累计积分将清空。': 'This party’s accumulated points will be cleared.',
  '创建派对': 'Create party',
  '该游戏没有可调整的选项': 'This game has no adjustable options',
  '人数': 'Players',
  '时长': 'Length',
  '约 5 分钟': 'About 5 min',
  '约 15 分钟': 'About 15 min',
  '30 分钟内': 'Under 30 min',
  '约 1 小时': 'About 1 hour',
  '难度': 'Difficulty',
  '入门': 'Beginner',
  '中等及以下': 'Intermediate or easier',
  '含进阶': 'Includes advanced',
  '玩法': 'Mode',
  '合作': 'Co-op',
  '对战': 'Competitive',
  '收藏': 'Favorites',
  '最近玩过': 'Recently played',
  '取消收藏': 'Remove favorite',
  '收藏当前游戏': 'Favorite this game',
  '取消收藏当前游戏': 'Remove this favorite',
  '收藏当前游戏（也可长按游戏）': 'Favorite this game (or long-press it)',
  '（长按 / 右键：{0}）': ' (long-press / right-click: {0})',
  '收藏（也可长按游戏）': 'Favorite (or long-press a game)',
  '第 {0}/5 步 · {1}': 'Step {0}/5 · {1}',
  '单机': 'Single-player',
};

/// English names for the game catalog. Descriptions that are not listed retain their Chinese
/// source, so no server protocol changes are needed when a new game is added.
const Map<String, String> auroraGameEnglish = {
  '围棋': 'Go',
  '国际象棋': 'Chess',
  '中国象棋': 'Xiangqi',
  '俄罗斯方块对战': 'Tetris Battle',
  '贪吃蛇大作战': 'Snake Battle',
  '扫雷竞速': 'Minesweeper Race',
  '2048对战': '2048 Battle',
  '数独竞速': 'Sudoku Race',
  '锄大地': 'Big Two',
  '炸金花': 'Three Card Poker',
  '斗牛': 'Bull Bull',
  '十三水': 'Chinese Poker',
  '够级': 'Gouji',
  '保皇': 'Bao Huang',
  '双扣': 'Shuangkou',
  'Gin Rummy': 'Gin Rummy',
  '港式麻将': 'Hong Kong Mahjong',
  '蜂巢': 'Hive',
  '格格不入': 'Blokus',
  '师徒棋': 'Onitama',
  'Quarto': 'Quarto',
  '国标麻将': 'Chinese Official Mahjong',
  '广东推倒胡': 'Guangdong Mahjong',
  '大富翁': 'Monopoly',
  '你画我猜': 'Draw and Guess',
  '传话画画': 'Telephone Pictionary',
  '卡卡颂': 'Carcassonne',
  '花火': 'Hanabi',
  '谁是牛头王': '6 nimmt!',
  'No Thanks!': 'No Thanks!',
  '寿司狗': 'Sushi Go!',
  '政变': 'Coup',
  '心灵同步': 'The Mind',
  '骷髅与玫瑰': 'Skull',
  '西洋双陆': 'Backgammon',
  '曼卡拉': 'Mancala',
  '六子棋': 'Connect6',
  '六角棋': 'Hex',
  '九子棋': 'Nine Men\'s Morris',
  '花砖物语': 'Azul',
  '王国骨牌': 'Kingdomino',
  '拼布艺术': 'Patchwork',
  '七大奇迹·对决': '7 Wonders Duel',
  '干瞪眼': 'Gandengyan',
  '五十K': 'Fifty K',
  '争上游': 'Zheng Shang You',
  '拱猪': 'Hearts (Chinese)',
  '百家乐': 'Baccarat',
  '德州扑克': 'Texas Hold\'em',
  '21点': 'Blackjack',
  '跑得快': 'Paodekuai',
  '德国心脏病': 'Halli Galli',
  '猜数字1A2B': 'Bulls and Cows',
  '海龟汤': 'Turtle Soup',
  '截码战': 'Decrypto',
  '一夜终极狼人': 'One Night Ultimate Werewolf',
  '飞行棋': 'Ludo',
  '跳棋': 'Chinese Checkers',
  '路墙棋': 'Quoridor',
  '炸飞机': 'Battleship',
  '达芬奇密码': 'Da Vinci Code',
  '记忆翻翻乐': 'Memory Pairs',
  '熄灯挑战': 'Lights Out',
  '字词拼图': 'Word Tiles',
  '狼人杀': 'Werewolf',
  '日本麻将（四人）': 'Japanese Mahjong (4P)',
  '日本麻将（三人）': 'Japanese Mahjong (3P)',
  '四川麻将': 'Sichuan Mahjong',
  '长沙麻将': 'Changsha Mahjong',
  '二人麻将': 'Two-player Mahjong',
  '井字棋': 'Tic-Tac-Toe',
  '五子棋': 'Gomoku',
  '黑白棋': 'Othello',
  '四子棋': 'Connect Four',
  '点格棋': 'Dots and Boxes',
  '国际跳棋': 'Checkers',
  '军棋': 'Chinese Army Chess',
  '斗兽棋': 'Jungle',
  '将棋': 'Shogi',
  '揭棋': 'Dark Chess',
  'UNO': 'UNO',
  '拉密': 'Rummikub',
  '桥牌': 'Bridge',
  '红心大战': 'Hearts',
  '黑桃王': 'Spades',
  '情书': 'Love Letter',
  '快艇骰子': 'Yahtzee',
  '璀璨宝石': 'Splendor',
  '骗子酒馆': 'Liar\'s Bar',
  '卡坦岛': 'Catan',
  '阿瓦隆': 'Avalon',
  '行动代号': 'Codenames',
  '代号：合作版': 'Codenames Duet',
  '谁是卧底': 'Undercover',
  '掼蛋': 'Guandan',
  '升级（拖拉机）': 'Shengji',
  '十点半': 'Ten and a Half',
  '骰子扑克': 'Dice Poker',
  '猪骰': 'Pig',
  '快乐骰': 'Farkle',
  '吹牛骰': 'Liar\'s Dice',
};

String auroraT(String source, [List<Object?> args = const []]) {
  var value = currentAuroraLanguage == AuroraLanguage.en
      ? (auroraEnglish[source] ?? source)
      : source;
  for (var i = 0; i < args.length; i++) {
    value = value.replaceAll('{$i}', '${args[i]}');
  }
  return value;
}

String auroraGameText(String source) =>
    currentAuroraLanguage == AuroraLanguage.en
    ? (auroraGameEnglish[source] ?? source)
    : source;

String auroraCategory(String source) {
  if (currentAuroraLanguage == AuroraLanguage.zhCN) return source;
  return const {
        '麻将': 'Mahjong',
        '棋类': 'Board games',
        '牌类': 'Card games',
        '桌游': 'Tabletop',
        '派对': 'Party',
      }[source] ??
      source;
}

/// Inherited language scope for code that has a BuildContext. The global helper above is kept
/// as well because server messages and local sessions are built outside widget trees.
class AuroraI18n extends InheritedWidget {
  final AuroraLanguage language;
  const AuroraI18n({super.key, required this.language, required super.child});

  static AuroraLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuroraI18n>()?.language ??
      currentAuroraLanguage;

  @override
  bool updateShouldNotify(AuroraI18n oldWidget) =>
      oldWidget.language != language;
}

extension AuroraTranslations on BuildContext {
  AuroraLanguage get auroraLanguage => AuroraI18n.of(this);
  String at(String source, [List<Object?> args = const []]) =>
      auroraT(source, args);
  String gameText(String source) => auroraGameText(source);
}

/// A const-friendly translated label for the common `const Text('…')` case. It lets the same
/// source stay in const widget trees while still responding to a language switch.
class AuroraText extends StatelessWidget {
  final String source;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  const AuroraText(
    this.source, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    // Register a dependency so const labels rebuild when the language changes.
    AuroraI18n.of(context);
    return Text(
      auroraT(source),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
