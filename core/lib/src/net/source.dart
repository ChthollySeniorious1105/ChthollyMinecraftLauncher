/// Game-file download source ("下载源").
enum DownloadSource {
  /// Mojang / loader official hosts.
  official('官方源'),

  /// BMCLAPI (bangbang93) mirror for game files, loaders and Java.
  bmclapi('BMCLAPI 镜像'),

  /// Mirror first, fall back to official.
  auto('自动（镜像优先，失败回退官方）');

  final String label;
  const DownloadSource(this.label);
}

/// Content (Mod / 整合包 / 光影 …) API source.
enum ContentSource {
  official('官方 API（Modrinth / CurseForge）'),
  mcim('MCIM 镜像');

  final String label;
  const ContentSource(this.label);
}

/// Rewrites official URLs onto mirrors.
abstract class Mirrors {
  static const bmcl = 'https://bmclapi2.bangbang93.com';

  static const _bmclMap = <String, String>{
    'https://launchermeta.mojang.com': bmcl,
    'https://launcher.mojang.com': bmcl,
    'https://piston-meta.mojang.com': bmcl,
    'https://piston-data.mojang.com': bmcl,
    'https://libraries.minecraft.net': '$bmcl/maven',
    'https://resources.download.minecraft.net': '$bmcl/assets',
    'https://files.minecraftforge.net/maven': '$bmcl/maven',
    'https://maven.minecraftforge.net': '$bmcl/maven',
    'https://maven.neoforged.net/releases': '$bmcl/maven',
    'https://meta.fabricmc.net': '$bmcl/fabric-meta',
    'https://maven.fabricmc.net': '$bmcl/maven',
    'https://meta.quiltmc.org': '$bmcl/quilt-meta',
    'https://maven.quiltmc.org/repository/release': '$bmcl/maven',
  };

  static String? toBmcl(String url) {
    for (final e in _bmclMap.entries) {
      if (url.startsWith(e.key)) return e.value + url.substring(e.key.length);
    }
    return null;
  }

  /// Candidate URLs in try-order for [url] under [src].
  static List<String> candidates(String url, DownloadSource src) {
    if (src == DownloadSource.official) return [url];
    final m = toBmcl(url);
    return [?m, url];
  }

  static const manifestOfficial = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';

  /// GitHub download acceleration prefix, e.g. `https://ghfast.top/`. Empty = direct.
  static String githubPrefix = '';

  static String github(String url) => githubPrefix.isEmpty ? url : '$githubPrefix$url';
}
