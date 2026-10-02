"""Builds lib/i18n/core_en.dart: English templates for messages produced by cml_core.
Order matches tool/core_strings_zh.txt (sorted). Lines with an empty translation are skipped
(internal strings: game log prefixes, the updater batch script)."""
from pathlib import Path

EN = r"""
Bad BDX header
BDX (FastBuilder)
BMCLAPI mirror
CML update
Chunker isn't installed yet — download it under Toolbox → Chunker
Chunker conversion failed (exit code {0}), log: {1}
Chunker needs Java 17 or newer
Clash Verge setup did not finish (exit code {0})
The official CurseForge API needs an API key — enter one in Settings or switch to the MCIM mirror
CurseForge modpack (.zip)
FabricSkyBoxes sky {0}: type {1} is not supported yet
FabricSkyBoxes sky {0} is missing face textures — skipped
GitHub API rate limit reached, please try again later
Java {0} (pack_format {1})
Java download failed
Java and Bedrock mostly use different translation keys; language files only apply to matching keys
Java core shaders can't be converted to Bedrock
Java version too old: choose a newer Java in Settings.
Java runtime {0} / {1}
MCEdit Schematic (legacy)
MCIM mirror
Minecraft Bedrock Edition
Minecraft Education Edition
Minecraft Preview
Mod conflict (Mixin apply failed): check the mods you added recently.
Incompatible mod versions: see the mods named in the log.
A mod is missing a dependency or is incompatible: see the dependencies named in the log.
Modrinth modpack (.mrpack)
Nuit sky {0} has more than 4 fade keyframes; OptiFine can keep only one fade in/out
Nuit sky {0}: texture {1} not found — skipped
Nuit sky {0} ({1}) has no OptiFine equivalent — skipped
Nuit skies → also generate OptiFine skies
OptiFine {0} download failed
OptiFine patching failed (exit code {0}): {1}
OptiFine skies → also generate Nuit skies
OptiFine Custom Item Textures (CIT) have no Bedrock equivalent
OptiFine Connected Textures (CTM) have no Bedrock equivalent
Xbox Live authorization failed






mcpatcher/ renamed to optifine/ ({0} files)
mihomo core
The mihomo core hasn't been downloaded yet

{0} {1} has no file for this computer
{0} download failed
{0} GUI textures not converted (the two editions have different UI layouts)
{0} Java block/item models can't be converted (Bedrock uses a completely different geometry system); those blocks keep their vanilla shape
{0} Bedrock model / entity / animation files can't be converted (Java doesn't support custom entity geometry without mods)
{0} file verification failed
{0} isn't installed — get it from the Microsoft Store
The animation of {0} has per-frame timings, which Bedrock doesn't support; converted with a uniform frame time
{0} (level.dat damaged)
{0} ({1})
{0} (shared)
Download Java {0}
Download OptiFine {0}
Download {0} {1}
Download incomplete
Download failed: {0}
Downloading installer
Downloading modpack files
Downloading modpack files {0} / {1}
Downloading files {0} / {1}
Downloading asset index
Unsupported file type: {0}
Not a BDX file
Not a CML instance pack
Not a resource pack (missing pack.mcmeta or manifest.json)
Disconnected from the multiplayer server
Both formats, completing each other
Optimizing memory
Xbox Live isn't available in your region
You declined the sign-in
Keep as is
Patching game files
Shaders
Global
Out of memory: allocate more memory to the game, or remove some mods/shaders.
Too much memory allocated or 32-bit Java: lower the memory or use 64-bit Java.
Core API error: {0}
Adventure
Sliced textures
Creative
No world found in the archive (missing level.dat)
Vanilla structure NBT
Native crash: usually a graphics driver or shader problem — update your driver or disable shaders.
Right leg
Right arm
Merged textures
Launch game
Looking up files on {0}
Bedrock Edition
Bedrock UI (JSON UI) can't be converted
Bedrock ray-tracing / PBR textures (texture_set, MER, normal maps) were kept as-is but vanilla Java won't use them
The Bedrock skybox was converted to an OptiFine custom sky and a Nuit sky (one of the two mods is needed to see it)
Bedrock structure
Bedrock Edition (.mcpack)
Bedrock (UWP)
Sky layer {0}/{1} uses days (per-day display), which Nuit doesn't support — ignored
Sky layer {0}/{1} uses speed={2}; in Nuit its starting angle may differ slightly from OptiFine
Sky layer {0}/{1} is missing texture {2} — skipped
Head
Duplicate mods: delete the duplicate files in the mods folder.
Installing Minecraft {0}
Installing {0} {1}
The installer is missing its universal file
The installer didn't create a version
Unrecognised installer format
The installer failed (exit code {0}); log saved to cml-installer.log
Full instance (.cmlpack, all files included)
Official APIs (Modrinth / CurseForge)
Official
Crash description: {0}
Left leg
Left arm
Cancelled
Converted Nuit skies to OptiFine custom skies (optifine/sky); the Nuit files were kept
Converted OptiFine custom skies to Nuit (assets/nuit/sky); the OptiFine files were kept, so both mods work
Upgraded legacy FabricSkyBoxes skies to Nuit; the original files were kept
Converted the first custom sky layer to the Bedrock skybox (overworld_cubemap); Bedrock skyboxes don't support time fades or layering
Snapshot
Minecraft {0} not found
Mojang Java runtime {0} not found
JSON file of version {0} not found
Re-assembled textures
Favourites
Data packs
Modpacks
File verification failed: {0}
Spectator
Can't use the downloaded Java {0}
Couldn't get download info for Java {0}
Couldn't get the version list — check your network or switch the download source
Unrecognised modpack format (supported: Modrinth .mrpack, CurseForge .zip and CML .cmlpack)
Can't read {0} (file damaged or wrong format)
Can't read {0}: {1}
Can't read the skin image (PNG required)
Graphics driver doesn't support OpenGL: update your graphics driver.
Automatic install of {0} isn't supported yet
Updated OptiFine configs
The update package has no cml.exe
Updated references
{0} files failed to download, e.g. {1}
Server identity changed (fingerprint {0}). If you didn't reinstall the server, someone may be impersonating it.
The server returned invalid data: {0}{1}
Server redirect without a location: {0}
Java {0} not found — downloading it automatically
Unknown
Unknown BDX instruction {0} (position {1})
No Azure app ID configured — sign in through microsoft.com/link instead, or enter one in Settings
Hardcore
Querying CurseForge
Querying Modrinth
Checking account
Signing in to Minecraft
Signing in to Xbox Live
Getting the XSTS token
Reading game profile
Release
No pending update
Game files missing or a mod is incompatible with this version: try repairing the files.
The game path contains special characters: move the game to a plain ASCII path.
Source and target are both Bedrock
Source and target versions are the same — only metadata and sky formats were updated
Version {0} already exists
JSON file of version {0} is damaged
Version {0} has a too deep or circular inheritance chain
Survival
Probably caused by these mods: {0}
The sign-in code expired, please sign in again
Session expired: please sign in to Microsoft again.
Skins must be 64×64 or 64×32
Direct
Missing required mods: install the dependencies named in the log.
Game jar {0} is missing — repair the files first
No response from the multiplayer server
Multiplayer connection error
Auto (mirror first, falls back to official)
Couldn't get the loader version list
Repairing game files
Rule
Extracting
Resolving {0} mods
Computing file fingerprints
The subscription isn't a Clash config (choose the Clash/Mihomo link in your provider's dashboard)
Subscription update failed (HTTP {0})
This BDX uses runtime block IDs and can't be read offline
This Microsoft account has no Xbox profile yet — create one at xbox.com first
This account doesn't own Minecraft: Java Edition or has no player name yet (set one in the official launcher first)
This account needs adult verification (South Korea)
Install Minecraft {0} first
Add a subscription first
Please sign in with a Microsoft account first
Finish the installation in the installer window
Request failed (HTTP {0}): {1}{2}
The sign-in of {0} expired, please sign in again
Resource packs
Body
Converted animations
Converted sky layers
Converted language files
Converted textures
Converted sounds
Running the installer (may take a few minutes)
This is a child account — a parent must add it to a family group before it can sign in
Old Alpha
Old Beta
Some sounds are in FSB format and can't be converted
Renamed files
Sound files go into the Bedrock pack under the same paths; most sound paths match between Java and Bedrock, so they replace vanilla sounds directly
Preview
Preview (UWP)
"""


def dart(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


keys = Path('tool/core_strings_zh.txt').read_text(encoding='utf-8').split('\n')
en = EN.strip('\n').split('\n')
if len(keys) != len(en):
    raise SystemExit(f'core key count {len(keys)} != translation count {len(en)}')
out = ['// GENERATED by tool/gen_core_en.py — English templates for cml_core messages.', 'const coreEn = <String, String>{']
for k, v in zip(keys, en):
    if v.strip():
        out.append(f'  {dart(k)}: {dart(v)},')
out.append('};')
Path('lib/i18n/core_en.dart').write_text('\n'.join(out) + '\n', encoding='utf-8')
print('wrote', sum(1 for v in en if v.strip()), 'core translations')
