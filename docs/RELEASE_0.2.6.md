# CML 0.2.6

## Aurora cleanup

- Removed the **Quiz Party** (知识派对) and **Aurora Escape Room** (极光密室) games.
- Removed daily challenges, including the activity screen and the server-side daily puzzle store.
- Room chat no longer posts "disconnected" / "reconnected" notices, so flaky connections stop flooding the chat. The member list still shows who is online.

## Upgrade

Build both clients and servers from the same tag. Replace the server executable and its complete `web/` directory together; keep `server_identity.key`, `aurora_server.json`, `.env`, `data/`, and `replays/`. `data/daily.json` is no longer read and can be deleted.

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1 -Version 0.2.6
powershell -ExecutionPolicy Bypass -File build-servers.ps1 -Version 0.2.6
```
