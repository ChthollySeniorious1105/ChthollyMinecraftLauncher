// English translations for the multiplayer area. Hand-maintained: key = Chinese source string used in trGlobal('…').
const stringsEnMultiplayer = <String, String>{
  // Bedrock Edition (UDP) rooms
  '没有检测到本机的基岩版世界。请在基岩版中打开世界并在设置 → 多人游戏中开启「对局域网玩家可见」，或启动 BDS 后重试。':
      'No local Bedrock world detected. Open a world in Bedrock and enable "Visible to LAN Players" under Settings → Multiplayer, or start BDS, then try again.',
  '请填写有效的 UDP 端口': 'Please enter a valid UDP port',
  '未检测到基岩版世界': 'No Bedrock world detected',
  '本机 UDP {0} 上没有响应。仍要创建房间吗？（游戏开启后朋友即可连接）':
      'Nothing answered on local UDP {0}. Create the room anyway? (Friends can connect once the game is running)',
  '仍然创建': 'Create anyway',
  '正在主持基岩版房间 {0}（本地 UDP {1}）': 'Hosting Bedrock room {0} (local UDP {1})',
  '服务器未开启公网 UDP 入口（或已被其他房间占用 / 房间设置了密码），仅 CML 玩家可加入':
      'The server has no public UDP entry enabled (or it is taken by another room / your room has a password); only CML players can join',
  '已加入基岩版房间 {0}': 'Joined Bedrock room {0}',
  '打开基岩版 → 好友 → 局域网游戏中会出现该房间。如果没有出现，请在「服务器」页添加服务器：':
      'Open Bedrock → Friends → LAN Games and the room will show up. If it does not, add a server on the "Servers" tab:',
  '本机 UDP 19132 已被占用（可能有基岩版服务器或其他程序在运行），局域网游戏列表中不会出现该房间。请在基岩版「服务器」页添加服务器：':
      'Local UDP 19132 is in use (a Bedrock server or another program may be running), so the room will not appear under LAN Games. Add a server on Bedrock\'s "Servers" tab:',
  '地址 127.0.0.1　端口 {0}': 'Address 127.0.0.1  Port {0}',
  '本地 UDP {0}': 'Local UDP {0}',
  '公网 UDP {0}': 'Public UDP {0}',
  '没有 CML 的玩家也可以在基岩版「服务器」页添加 {0}，端口 {1}。注意：这等同于把你的世界公开到互联网，任何知道地址的人都能连接。':
      'Players without CML can also add {0}, port {1} on Bedrock\'s "Servers" tab. Note: this publishes your world to the internet; anyone who knows the address can connect.',
  '1. 打开基岩版世界，在 设置 → 多人游戏 中开启「对局域网玩家可见」（或运行 BDS 基岩版服务器）\n2. 点击「检测」确认 UDP 端口（默认 19132），然后创建房间':
      '1. Open a Bedrock world and enable "Visible to LAN Players" under Settings → Multiplayer (or run a Bedrock Dedicated Server)\n2. Click "Detect" to confirm the UDP port (default 19132), then create the room',
  '本地 UDP 端口': 'Local UDP port',
  '检测': 'Detect',
  '{0}/{1} 人': '{0}/{1} players',
  '公网直连': 'Public direct connect',
  '需服主开启 --public-udp；无密码房间才可用': 'Requires the server owner to enable --public-udp; password-less rooms only',
  '开启后没有 CML 的玩家也能直接用 CMLS 服务器地址连接你的世界，相当于把世界公开到互联网，请确认世界的权限设置。':
      'When enabled, players without CML can connect to your world directly through the CMLS server address. This is the same as publishing your world to the internet; check your world\'s permission settings.',
  '基岩版房间同样只走这个 TCP 端口。可选：加 --public-udp 19132 开启基岩版公网入口，让没有 CML 的玩家直接添加服务器连接被公开的房间（需额外放行 UDP 端口，等同于公开房主的世界）。':
      'Bedrock rooms use the same TCP port. Optional: add --public-udp 19132 to open a public Bedrock entry so players without CML can add the server and join the exposed room (the UDP port must also be opened; this publishes the host\'s world).',
};
