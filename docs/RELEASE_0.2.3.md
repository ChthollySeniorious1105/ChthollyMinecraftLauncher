# CML 0.2.3

## Aurora 更新

- 新增 **5 款游戏**，总数达到 **117 款**：知识派对、记忆翻翻乐、极光密室、熄灯挑战、字词拼图。
- 新增 **派对之夜**：2～8 款游戏连玩、投票选下一局、跨游戏积分、总冠军。
- 新增 **房间二维码与邀请链接**：手机扫码用浏览器打开，CML 可粘贴含客户端地址的链接加入。
- 新增 **游戏筛选与随机推荐**：按人数、预计时长、难度、合作或对战选择。
- 新增 **每日数独、扫雷、2048、熄灯挑战**：同服同题，服务端校验操作，记录个人最好成绩与每日排行榜。
- 新增 **6 个互动新手练习**：分步提示、演示、自由练习，支持离线。
- 改善手机切回页面、网页刷新后的重连体验；修复 CML 内置面板宽度判断。
- 新功能的界面、游戏规则、题库、错误提示均使用 **简体中文**。CML 客户端与手机 / 电脑网页版可同房游玩。

## 下载

- `CML-0.2.3-windows-x64.zip`：Windows 启动器主包。
- `Aurora-server-0.2.3-windows-x64.zip`：Aurora 服务端，包含已构建的网页版。
- `CMLS-0.2.3-windows-x64.zip`、`Pulse-server-0.2.3-windows-x64.zip`：联机中继与 Pulse 服务端。
- `CML-servers-src-0.2.3.zip`：服务端源码及依赖，包含 Aurora 网页客户端源码。
- `CML-addon-pulse-ai-models-0.2.3.zip`、`CML-addon-pulse-ai-voices-0.2.3.zip`：可选 AI 模型与音色分包；`cml-addons.json` 供启动器识别。
- `SHA256SUMS.txt`：所有发布文件的 SHA-256 校验值。

## 升级说明

Aurora 协议为 **v4**，请同步更新客户端与 Aurora 服务端。关闭旧服务端后替换程序与整个 `web/` 文件夹；保留 `server_identity.key`、`aurora_server.json`、`.env`、`data/` 和 `replays/`。每日挑战按 UTC 日期换题，已完成成绩保存在 `data/daily.json`；未完成进度在服务端重启后重置。

要生成手机和 CML 都能使用的邀请，在 Aurora 服务端 `.env` 设置 `PUBLIC_WEB_URL`（可访问的 HTTP/HTTPS 网页地址）与 `PUBLIC_TCP_ADDRESS`（原生客户端地址）。房间密码不会写入二维码或链接。

构建入口：`build.ps1 -Version 0.2.3` 与 `build-servers.ps1 -Version 0.2.3`。
