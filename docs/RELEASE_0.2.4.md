# CML 0.2.4

## Aurora multilingual UI and typography

- Aurora now supports Simplified Chinese (`zh-CN`) and English (`en`) in the standalone web client, the CML embedded client, and local games.
- The language follows CML's language setting when Aurora is embedded. The standalone web client remembers its choice in the browser and defaults to the browser language when no choice has been saved.
- Game names, categories, room tools, invites, daily challenges, replays, settings, party nights, and the main Aurora controls use the selected language. The protocol and server data stay compatible with v4 servers.
- `ClaudeSansStd.OTF` is bundled for English UI text with CJK and emoji fallbacks. The same font is used by the Windows client and Aurora web loading page.

## Included Aurora content

Aurora still includes 117 games, Party Night queues, QR / HTTP invitations, game filters, daily challenges, and interactive tutorials from 0.2.3. The CML desktop client and the phone / desktop web client share the same rules and protocol.

## Upgrade

Build both clients and servers from the same tag. Replace the server executable and its complete `web/` directory together; keep `server_identity.key`, `aurora_server.json`, `.env`, `data/`, and `replays/`.

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -Version 0.2.4
powershell -ExecutionPolicy Bypass -File build-servers.ps1 -Version 0.2.4
```
