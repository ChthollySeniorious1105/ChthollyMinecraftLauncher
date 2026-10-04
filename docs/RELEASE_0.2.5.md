# CML 0.2.5

## Aurora fixes and interface font

- Fixed the Aurora UI breaking after switching to Simplified Chinese. Text fields, dialogs and tooltips now load their Simplified Chinese (`zh-Hans-CN`) strings in the standalone web client and in the CML embedded client.
- New **Settings → Interface font** option. It lists every font installed on the system, previews each one in its own typeface, and can be searched by English or Chinese name (for example `Microsoft YaHei` / `微软雅黑`). Claude Sans and the CJK / emoji fonts stay as fallbacks for missing characters. **Reset** returns to the bundled Claude Sans. The web client keeps the bundled font because browsers do not expose installed fonts.
- Fixed layout overflows on narrow screens: the lobby room card footer, long English game names on room cards, and the room header on phones.
- The player count in the room header is now translated.

## Upgrade

Build both clients and servers from the same tag. Replace the server executable and its complete `web/` directory together; keep `server_identity.key`, `aurora_server.json`, `.env`, `data/`, and `replays/`.

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -Version 0.2.5
powershell -ExecutionPolicy Bypass -File build-servers.ps1 -Version 0.2.5
```
