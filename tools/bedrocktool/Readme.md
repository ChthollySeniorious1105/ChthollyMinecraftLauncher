# BedrockTools

这是独立维护的 BedrockTools 工作区版本，当前适配 Minecraft Bedrock Edition 26.52（协议 2193）。

- **协议更新流程（权威）**：[PROTOCOL_UPDATE.md](PROTOCOL_UPDATE.md)
- 历史适配记录：[V26.52_ADAPTATION.md](V26.52_ADAPTATION.md)、[V26.44_ADAPTATION.md](V26.44_ADAPTATION.md)、[BEDROCKTOOL_VERSION_UPGRADE_GUIDE.md](BEDROCKTOOL_VERSION_UPGRADE_GUIDE.md)
- 在 CML 中的使用：启动器「基岩版工具」页面（`launcher/lib/pages/bedrock_tools_page.dart`）通过 `core/lib/src/bedrock/bedrocktool.dart` 调用本 CLI；数据目录 `%APPDATA%\CML\bedrocktool`（token.json、worlds、skins、captures…）。

项目不依赖外部仓库的旧版本发布物；协议更新以 Mojang 官方协议文档为准。

```
Usage: bedrocktool <subcommand> [-flag=value ...]      各子命令参数：bedrocktool <subcommand> -h=true

  worlds         download a world from a server
  skins          download skins from players on a server
  capture        capture packets in a pcap file
  chat-log       logs chat to a file
  list-realms    prints all realms you have access to
  realm-address  gets realms address
  merge          merge worlds
  render         render a world to png
  debug-proxy    verbose debug packets
  dump-actors    dump and write actors
  packs          download resource packs from a server
  （subcommands/resourcepack-d/ 包是 git-crypt 密文，仅 -tags packs 时编译，CML 构建不包含；不影响 packs 命令）
```

CML 构建（CLI，离线 Go 工具链与模块缓存，输出 `out\bedrocktool.exe`；`out\` 已被 .gitignore 忽略）：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 [-GoRoot <go>] [-ModCache <go-mod-cache>] [-Version v26.52-cml] [-SkipTests]
```

仓库根目录的 `build.ps1` 会调用它，并把 exe 复制到 `dist\CML\tools\bedrocktool\`。
