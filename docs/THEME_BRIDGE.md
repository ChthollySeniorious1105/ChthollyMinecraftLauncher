# CML 主题桥（theme.json）

CML 是唯一的主题来源。CML 每次切换主题 / 深浅色 / 强调色时写入：

    %APPDATA%\CML\theme.json

CML 启动外部内置应用（DesktopPet、LiteEditor、LiteReader、LumiKeyMapper）时还会设置环境变量
`CML_THEME_FILE` 指向该文件。应用查找顺序：`CML_THEME_FILE` → `%APPDATA%\CML\theme.json` → 内置默认配色。
应用必须监视该文件（fs.watch / FileSystemWatcher），变化后实时换色；解析失败时保持当前配色。

```json
{
  "version": 1,
  "id": "chtholly",
  "name": "珂朵莉蓝",
  "dark": false,
  "bg": "#f4f7fa",        // 页面背景
  "surface": "#ffffff",   // 卡片 / 对话框
  "panel": "#ffffff",     // 侧栏 / 面板
  "text": "#1d2233",      // 主文字
  "muted": "#6b7280",     // 次要文字
  "line": "#e3e7ec",      // 边框 / 分隔线
  "field": "#f3f5f8",     // 输入框 / 按钮底色
  "accent": "#4fa3d9",    // 主色
  "accent2": "#7fd3c8",   // 辅助色（渐变第二色）
  "onAccent": "#ffffff",  // 主色上的文字
  "paper": "#ffffff",     // 阅读 / 编辑区纸张
  "ink": "#23283a",       // 纸张上的文字
  "art": ["#4fa3d9", "#7fd3c8"]  // 背景装饰渐变色
}
```

所有颜色均为 `#rrggbb`。新增字段只会追加，应用应忽略未知字段。
