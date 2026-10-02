"""Builds lib/i18n/strings_en.dart from tool/strings_zh.txt + the English list below (same order as the sorted keys).
Fails loudly if the key list changed so translations never drift out of sync."""
from pathlib import Path

EN = r"""
 and the game
1. Start the game, open a singleplayer world → Esc → "Open to LAN"\n2. Come back here and click "Create room"; CML detects the port automatically
1. Connect to a server
2. Create or join
3. Play
32-bit
Azure app
Azure app ID
CML supports genuine Microsoft accounts only
CMLS is CML's multiplayer relay server (cmls.exe). Run it on any machine with a public IP or a tunnel:\n  cmls.exe --port 25590 --name "My server"\nThe first start creates server_identity.key (the server identity — back it up, never share it) and prints the server fingerprint. Only the TCP port needs to be opened / forwarded.
CMLS multiplayer server
Chunker world conversion
Chunker is Hive Games' open-source Java ⇄ Bedrock world converter. CML downloads its command-line version from GitHub (about 30 MB) and keeps it updated.
Chunker needs Java 17 or newer. Install it under Download → Java first
Clash Verge Rev (full app)
Files found on CurseForge are stored as project IDs; everything else is bundled
GitHub download prefix
JVM arguments
Java & memory
Any Java version ⇄ any version · Java ⇄ Bedrock · OptiFine ⇄ Nuit skies · texture slicing/merging, model references, CTM/CIT migrated too
Java Edition
Manage, back up and convert Java & Bedrock worlds
Java runtimes
Java, memory, download sources, account and appearance
Microsoft Store games
Minecraft 1.20.5+ needs Java 21; 1.18 – 1.20.4 need Java 17; 1.17 needs Java 16; 1.16.5 and older work best with Java 8.\nWith the "BMCLAPI" or "Auto" source, the Tsinghua mirror is preferred.
Minecraft {0}  ·  needs Java {1}+  ·  {2} libraries
Mod / content source
Files found on Modrinth are stored as download links; the rest is bundled — small file size
OptiFine {0} recommends {1}
OptiFine version
TUN mode
https://… (Clash / Mihomo format)
The mihomo core and Chunker check GitHub for new versions at startup
v{0} · Premium
{0} · current: {1}
{0} · host {1} · {2} players{3}
{0}0K
{0}
{0} tasks running
{0} versions
{0} versions, latest {1}
{0} versions, latest {1} (via BMCLAPI)
{0}00M
{0} screenshots
{0} version
{0}'s world
expires in {0}:{1}
{0}\n\nOnly continue if you know the server was reinstalled.
{0}\n{1}{2} downloads · {3}
{0}: {1}×{2}×{3}, {4} blocks, {5} block entities, {6} entities
⚠ Server identity changed
✓ {0}  {1}×{2}×{3}, {4} blocks{5}
"{0}" has no versions from the current game directory yet\nClick the star next to a version to add it
Optimize memory
Seven-colour flower
Upload as premium skin
Upload skin
Nether
Download
Download Chunker
Download Clash Verge Rev
Download Java {0}
Download Java (Eclipse Temurin)
Download mihomo core
Download {0}
Download threads
Downloads
Not available for this version
None
Synced with the in-game multiplayer list (servers.dat)
files
Theme
Errors & warnings only
Turn off anyway
Proxy
Code copied — just paste it
Tasks
Tasks finished
Any loader
Cheats
Needed for the official CurseForge API
Use the account that owns Minecraft: Java Edition
Java to use
e.g. -XX:+UseZGC
e.g. https://ghfast.top/ (empty = direct)
e.g. Survival, Modpacks, PVP
Save
Do nothing
Trust new identity
Change game mode / cheats
Stop
Allow cheats
Shaders
Fullscreen
Select all / none
All
Refresh all
Everything is up to date
Shared worlds
Shared worlds (.minecraft/saves)
Shared (.minecraft)
Public
{0} GB total, {1} GB available
Close
Without certificate checks, login requests can be intercepted. Only turn this off temporarily if a company/school proxy breaks login.
Close room
Disable certificate verification
Off (share .minecraft)
Other directory · {0}
Memory
Memory optimization
Memory {0}% used
Built-in Clash Verge proxy (mihomo core)
Adventure
Ready for an adventure?
Lighten
Switch to light mode
Switch to dark mode
Create room
Create a room (I host)
Creative
Initialization error: {0}
Delete
Delete {0}
Delete {0}?
Delete "{0}"? The versions in it are not deleted.
Delete "{0}"? It is backed up to the CML backup folder first.
Delete world
Delete screenshot
Delete folder
Delete server
Delete version
Delete subscription
Expires {0}
Refresh
Refresh room list
Refresh version list
Refresh login
Refresh account {0}
Join
Join a room
Darken
Loading…
Action strategy game.
Include pre-releases
Includes the version files and everything selected; can be imported offline into any CML
Included files (about {0})
Vanilla (no loader)
Get it
New version {0}
Cancel
Pick colour
Save as
Only changes the world's default; each player's own mode is stored in their player data. A backup is made first.
Available memory increased by about {0} MB{1}.
Move right
Also install OptiFine (as a mod)
Also clear the system standby cache
Name
Launch
Launch {0}
Launch {0} and join {1}
Launch {0}.bat
Launching…
Optimize memory before launch
Command before launch
After launch, the launcher
Join server after launch
Launcher
Route launcher downloads through the proxy
Launch game
Optimize memory before launching
Play with friends — no public IP needed
Store games
Images
Convert whole worlds between Java and Bedrock, or between game versions (HiveGamesOSS/Chunker, auto-updated from GitHub). You can also convert a single world from the Worlds page.
Show in folder
The new Dungeons game.
Dungeon-crawling action game.
Bedrock Edition
Launch Bedrock, Legends and Dungeons in one click
Bedrock data folders
Bedrock preview — try new features early.
Bedrock Edition (Windows) — crossplay with mobile and consoles.
Fill
Enter the CMLS server address; its fingerprint is remembered on first connect
Back up
Back up {0}
Backup folder
Copy all
Copy to
Copy to another version
Copy image
Copy address
Copy world
Copy room code
Overlay
Appearance
Sky
Failed: {0}
Worlds
World name
World conversion (Chunker{0})
Install
Install Minecraft {0}
Install {0}
Install into which world?
Install into version
Install modpack {0}
Done
Instance name
Width
Import
Import to
Import world
Import modpack {0}
Import local modpack
Import subscription {0}
Export
Export {0}
Export as modpack / instance
Export here
Export launch script
Export instance {0}
The official latest installer will be downloaded from GitHub (clash-verge-rev/clash-verge-rev) and opened; you confirm the installation in the installer. Continue?
Set the current skin ({0} model) as {1}'s premium skin?
LAN worlds are forwarded through an encrypted tunnel; friends see your room in Multiplayer
Toolbox
Move left
Saved
Joined {0}
Joined room {0}
Cancelled
Backed up to {0}
Copied to clipboard
Installed {0}
Installed versions
Exported (the script contains your login token — do not share it)
Exported: {0} files downloaded from the platform, {1} files bundled
Broken
Favourited (right-click to choose folders)
Optimized the memory of CML{0}; available memory increased by about {1} MB{2}
Disconnected: {0}
Already up to date
Updated {0} files; old files were moved to the .cml-old folder
{0} GB used / {1} GB total, {2} GB available
Signed in
Left the room
Connected to {0} (fingerprint {1})
Structure files
Structure file conversion
Structure, resource pack and world conversion, memory optimization
On (mods, worlds etc. live in the version folder)
Convert
Force-stop the game? Unsaved progress will be lost.
Current
Using the MCIM mirror — change it in Settings.
No versions installed in this game directory yet. Install one on the Download page.
Current version
This account has no custom skin
Needs refresh
Microsoft login needs an Azure app ID approved by Mojang (aka.ms/mce-reviewappid)
Required (a Mojang-approved app)
Snapshots
My room {0}
Screenshots
The host opens the world to LAN and creates a room; friends enter the room code
Room code
Room name (optional)
Room password
Room password (optional)
Room password (if any)
Room closed: {0}
The room now appears in Minecraft's Multiplayer list (LAN worlds). If it doesn't, add this server manually:
The room shows up in the multiplayer list automatically — just join it
All multiplayer traffic is end-to-end encrypted to the CMLS server with X25519 + ChaCha20-Poly1305; the server identity is remembered on first connect and you're warned if it changes.
Manual
Add manually
Open
Open
Open microsoft.com/link
Open containing folder
Open folder
Open project page
Extensions
Game directory not found: {0}
Send the room code to your friends: they connect to the same CMLS server in CML and enter the code. The room closes when CML or the game world closes.
Cape
Drop structure files here, or click "Add files"
Drop a resource pack (.zip / .mcpack / folder) here, or choose one on the right
Drag to rotate · scroll to zoom · double-click to reset
Search {0}
Search {0} ({1} total)
Search worlds
Search logs
Search versions
Search version number
Undo
Converts between .schematic (MCEdit), .schem (WorldEdit/Sponge), .litematic (Litematica), .nbt (vanilla structure block), .mcstructure (Bedrock structure) and .bdx (FastBuilder). Blocks are mapped automatically between Java and Bedrock.
Favourites
Favourite {0}
Favourite (right-click to choose folders)
Education Edition (needs a school/organisation account).
Data packs
Data folder
Modpacks
Modpack name
Modpack instance name
Trims the memory of CML and the running game, returning unused pages to the system. Only affects processes started by CML.
Folder
Disconnect
New
New folder
Spectator
None
Unrecognised files ({0})
Can't connect
Logs
Brightness
Update now?
Update CML now?
More world actions (backup, conversion, import/export) are on the Worlds page.
Update CML
Update CML {0}
Update Chunker
Update mihomo core
Update {0} {1}
Update {0} files
Updated {0}
Update to latest
Update and restart
Update selected ({0})
Update subscription
Update subscription {0}
Maximum memory
Maximize
Minimize
Newest
Latest snapshot
Latest release
Recently updated
Servers
Server name
Server address
Server password (optional)
Not installed
Not found
Not signed in
Unknown version
Couldn't determine the cause automatically — please check the log.
Stopped
Nothing selected
The End
Info / material list
Chosen from the mod count, game version and free memory, leaving headroom for the system
Checked {0} files: {1} can be updated, {2} unrecognised (not published on a platform)
Check core updates
Check for updates
Sakura
Eraser
Welcome to CML
Welcome back, {0}
Hosting room {0} (local port {1})
Getting a sign-in code…
Connecting…
Release
Release
Verify SSL certificates when signing in
Each version gets its own mods, worlds and config folders
No {0}\nSearch and install them on the Download page
No tasks
No public rooms
No versions installed
No Java worlds found
No Bedrock worlds found\n(install Bedrock from the Microsoft Store and enter a world once)
Bedrock world folder not found (launch Bedrock once first)
No Bedrock data found (enter a world once after installing)
No game opened to LAN was detected. In game press Esc → "Open to LAN", or enter the port manually.
No results
No files for this version
Nothing to migrate
Traffic {0} / {1}
Test latency
Authorized in the browser — fetching your game profile
Deepslate
Dark mode
Add files
Add server
Add game directory
Add subscription
Add account
Clear system standby cache
Clear
Game
Game, loaders, mods, modpacks, shaders, resource packs, data packs and Java
Game arguments
The game crashed
Game file source
Game log
Game mode
The game is running
Game version
Game running
Click to copy the code
Click to sign in with Microsoft
Click to launch · right-click a version to change folders
Versions
Version {0}
Version {0} has no worlds — can't install data packs
Version
Version name
Java versions
Broken version files
Version isolation
Physical memory
Players
Chtholly blue
Survival
Used to download Chunker, mihomo, CML updates and other GitHub files
Open in Notepad
Pencil
UI scale
Leave empty to use the built-in ID
Sign in with Microsoft
Sign in with Microsoft to start playing
Sign-in method
Skins
Skin PNG
Skin updated
Target format
Relevance
OK
Delete {0}? The version folder (including its mods and worlds) will be removed.
Remove {0}?
Leave
Remove
Remove account
Window size
Optimize now
Port (auto-detect)
Waiting for you to finish signing in in the browser
Filter game version
Manage installed versions, mods, resource packs and shaders
System
System proxy
Amethyst
Redstone
Slim (Alex)
Classic (Steve)
Classic blue
Stop game
Draw skins, 3D preview, upload and cape switching
Edit
Edit folder
Edit server
Network proxy
Multiplayer
Background image
Automatic
Automatic memory allocation
Scan automatically
Update built-in tools automatically
Update the launcher automatically
Automatic (picks the right Java for each version, downloads it if missing)
Automatic (next to the original world)
Hue
Nodes
Grass block
Behavior packs
Repair {0}
Repair files
Subscriptions
Subscription name
Subscription link
Settings
Detected: {0}
Please install Java first
Please sign in with a Microsoft account first
Please sign in first
Load current skin
Accounts
Resource packs
Resource pack conversion
Same as global
Same as global setting{0}
Convert {0} structure files
Convert to
Conversion creates a new world folder; the original world is not modified.
Convert world
Convert world → {0}
Convert version (Chunker)
Convert resource pack → {0}
Enter the code below and sign in with your Microsoft account
Input world
Output to
Output to this folder
Running · {0}
Restore
No saved servers yet
No screenshots yet\nPress F2 in game to take one
No account yet. Click "Add account" and enter the code at microsoft.com/link to sign in.
No subscriptions yet. Add a Clash / Mihomo subscription link from your provider.
This is not a valid Java
This version has no worlds yet
This version has no logs yet
This account has no capes (capes come from Minecraft events, the Migrator, etc.).
This makes Windows discard every program's file cache (it is re-read later) and requires running CML as administrator. Turn it on?
Old versions
Connect
Exit code {0}
Choose
Choose the .minecraft folder
Choose world folder
Select a version on the left
Choose file
Choose folder
Pick a version and start playing
Choose colour
Play with friends securely through a CMLS server
Check whether this version's mods, resource packs and shaders have newer releases on Modrinth and CurseForge\nOld files are backed up before updating
Hosting CMLS
Redo
Rename
Rename / icon
Rename world
Rename version
Detect again
Get a new code
Retry
Gold block
Diamond
Extra JVM arguments
Appended after the default arguments
Extra game arguments
Start with CML
Needs administrator
When you need Clash Verge Rev's full UI (rule editing, scripts, overrides…), install or update the official latest version with one click — use it instead of the built-in proxy.
Saturation
Height
Advanced
Off by default. Only works when running as administrator
 (including system cache)
 (converted Java ⇄ Bedrock blocks)
 (this version needs Java {0}+)
 (beta)
, and cleared the system cache
"""


def dart(s):
    # keys/values hold Dart escape sequences as written in source (e.g. \n); keep them as escapes
    BS = chr(92)
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == BS and i + 1 < len(s) and s[i + 1] in 'n':
            out.append(BS + 'n')
            i += 2
            continue
        if c == BS:
            out.append(BS + BS)
        elif c == "'":
            out.append(BS + "'")
        elif c == '$':
            out.append(BS + '$')
        else:
            out.append(c)
        i += 1
    return "'" + ''.join(out) + "'"


keys = Path('tool/strings_zh.txt').read_text(encoding='utf-8').split('\n')
en = EN.strip('\n').split('\n')
if len(keys) != len(en):
    raise SystemExit(f'key count {len(keys)} != translation count {len(en)} — update EN in tool/gen_strings_en.py')
lines = ['// GENERATED by tool/gen_strings_en.py — edit translations there.', 'const stringsEn = <String, String>{']
for k, v in zip(keys, en):
    lines.append(f'  {dart(k)}: {dart(v)},')
lines.append('};')
Path('lib/i18n/strings_en.dart').write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('wrote', len(keys), 'translations')
