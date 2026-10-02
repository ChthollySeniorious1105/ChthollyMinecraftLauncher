import '../common/errors.dart';
import '../net/http.dart';
import '../net/source.dart';

/// What kind of content to search for.
enum ContentType {
  mod('Mod', 'mod', 6, 'mods'),
  modpack('整合包', 'modpack', 4471, ''),
  shader('光影', 'shader', 6552, 'shaderpacks'),
  resourcepack('资源包', 'resourcepack', 12, 'resourcepacks'),
  datapack('数据包', 'datapack', 6945, 'datapacks');

  final String label;

  /// Modrinth `project_type`.
  final String modrinth;

  /// CurseForge `classId` (game 432).
  final int curseClass;

  /// Folder inside the game directory (datapacks go into a world's `datapacks`).
  final String folder;
  const ContentType(this.label, this.modrinth, this.curseClass, this.folder);
}

enum ContentPlatform { modrinth, curseforge }

class ContentProject {
  final ContentPlatform platform;
  final String id;
  final String slug;
  final String title;
  final String description;
  final String author;
  final String? iconUrl;
  final int downloads;
  final List<String> categories;
  final List<String> gameVersions;
  final List<String> loaders;
  final DateTime? updated;
  final ContentType type;

  ContentProject({
    required this.platform,
    required this.id,
    required this.slug,
    required this.title,
    required this.description,
    required this.author,
    required this.iconUrl,
    required this.downloads,
    required this.categories,
    required this.gameVersions,
    required this.loaders,
    required this.updated,
    required this.type,
  });

  String get pageUrl => platform == ContentPlatform.modrinth
      ? 'https://modrinth.com/${type.modrinth}/$slug'
      : 'https://www.curseforge.com/minecraft/${switch (type) {
          ContentType.mod => 'mc-mods',
          ContentType.modpack => 'modpacks',
          ContentType.shader => 'shaders',
          ContentType.resourcepack => 'texture-packs',
          ContentType.datapack => 'data-packs',
        }}/$slug';
}

class ContentFile {
  final String url;
  final String filename;
  final String? sha1;
  final int size;
  final bool primary;
  ContentFile(this.url, this.filename, this.sha1, this.size, this.primary);
}

class Dependency {
  final String projectId;
  final String? versionId;
  final bool required;
  Dependency(this.projectId, this.versionId, this.required);
}

class ContentVersion {
  final ContentPlatform platform;
  final String id;
  final String projectId;
  final String name;
  final String versionNumber;
  final List<String> gameVersions;
  final List<String> loaders;
  final String channel; // release / beta / alpha
  final DateTime published;
  final List<ContentFile> files;
  final List<Dependency> dependencies;
  final int downloads;

  ContentVersion({
    required this.platform,
    required this.id,
    required this.projectId,
    required this.name,
    required this.versionNumber,
    required this.gameVersions,
    required this.loaders,
    required this.channel,
    required this.published,
    required this.files,
    required this.dependencies,
    required this.downloads,
  });

  ContentFile get primaryFile => files.firstWhere((f) => f.primary, orElse: () => files.first);
}

enum SortBy { relevance, downloads, updated, newest }

/// Modrinth + CurseForge client with MCIM mirror support.
class ContentApi {
  final Http http;
  ContentSource source;

  /// Official CurseForge API key (needed for official source; MCIM works without one).
  String curseforgeKey;

  ContentApi(this.http, {this.source = ContentSource.mcim, this.curseforgeKey = ''});

  static const _mcim = 'https://mod.mcimirror.top';

  String get _mr => source == ContentSource.mcim ? '$_mcim/modrinth/v2' : 'https://api.modrinth.com/v2';
  String get _cf => (source == ContentSource.mcim || curseforgeKey.isEmpty) ? '$_mcim/curseforge/v1' : 'https://api.curseforge.com/v1';
  Map<String, String> get _cfHeaders => _cf.startsWith('https://api.curseforge.com') ? {'x-api-key': curseforgeKey} : const {};

  /// File URL candidates: mirror first when using MCIM.
  List<String> fileUrls(String url) {
    if (source != ContentSource.mcim) return [url];
    if (url.startsWith('https://cdn.modrinth.com/')) return ['$_mcim/${url.substring('https://cdn.modrinth.com/'.length)}', url];
    for (final h in ['https://edge.forgecdn.net/', 'https://mediafilez.forgecdn.net/']) {
      if (url.startsWith(h)) return ['$_mcim/${url.substring(h.length)}', url];
    }
    return [url];
  }

  // ---------------- search ----------------

  Future<List<ContentProject>> search(
    ContentPlatform platform,
    ContentType type, {
    String query = '',
    String? gameVersion,
    String? loader,
    String? category,
    SortBy sort = SortBy.relevance,
    int offset = 0,
    int limit = 30,
  }) =>
      platform == ContentPlatform.modrinth
          ? _mrSearch(type, query, gameVersion, loader, category, sort, offset, limit)
          : _cfSearch(type, query, gameVersion, loader, sort, offset, limit);

  Future<List<ContentProject>> _mrSearch(ContentType type, String q, String? gv, String? loader, String? cat, SortBy sort, int offset, int limit) async {
    final facets = <List<String>>[
      ['project_type:${type.modrinth}'],
      if (gv != null && gv.isNotEmpty) ['versions:$gv'],
      if (loader != null && loader.isNotEmpty && (type == ContentType.mod || type == ContentType.modpack)) ['categories:$loader'],
      if (cat != null && cat.isNotEmpty) ['categories:$cat'],
    ];
    final idx = switch (sort) { SortBy.relevance => 'relevance', SortBy.downloads => 'downloads', SortBy.updated => 'updated', SortBy.newest => 'newest' };
    final facetJson = '[${facets.map((f) => '[${f.map((e) => '"$e"').join(',')}]').join(',')}]';
    final u = Uri.parse('$_mr/search').replace(queryParameters: {'query': q, 'facets': facetJson, 'index': idx, 'offset': '$offset', 'limit': '$limit'});
    final j = await _get(u) as Map;
    return [
      for (final h in j['hits'] as List)
        ContentProject(
          platform: ContentPlatform.modrinth,
          id: '${h['project_id']}',
          slug: '${h['slug']}',
          title: '${h['title']}',
          description: '${h['description'] ?? ''}',
          author: '${h['author'] ?? ''}',
          iconUrl: h['icon_url'] as String?,
          downloads: (h['downloads'] as num?)?.toInt() ?? 0,
          categories: [for (final c in (h['display_categories'] as List? ?? [])) '$c'],
          gameVersions: [for (final c in (h['versions'] as List? ?? [])) '$c'],
          loaders: [for (final c in (h['categories'] as List? ?? [])) if (_loaders.contains(c)) '$c'],
          updated: DateTime.tryParse('${h['date_modified']}'),
          type: type,
        )
    ];
  }

  static const _loaders = {'fabric', 'forge', 'neoforge', 'quilt', 'liteloader', 'iris', 'optifine', 'canvas', 'vanilla'};

  static const _cfLoader = {'forge': 1, 'fabric': 4, 'quilt': 5, 'neoforge': 6};

  Future<List<ContentProject>> _cfSearch(ContentType type, String q, String? gv, String? loader, SortBy sort, int offset, int limit) async {
    final sortField = switch (sort) { SortBy.relevance => 1, SortBy.downloads => 6, SortBy.updated => 3, SortBy.newest => 11 };
    final params = <String, String>{
      'gameId': '432',
      'classId': '${type.curseClass}',
      'searchFilter': q,
      'sortField': '$sortField',
      'sortOrder': 'desc',
      'index': '$offset',
      'pageSize': '$limit',
      if (gv != null && gv.isNotEmpty) 'gameVersion': gv,
      if (loader != null && _cfLoader[loader] != null && type == ContentType.mod) 'modLoaderType': '${_cfLoader[loader]}',
    };
    final j = await _get(Uri.parse('$_cf/mods/search').replace(queryParameters: params), headers: _cfHeaders) as Map;
    return [for (final m in j['data'] as List) _cfProject(m as Map, type)];
  }

  ContentProject _cfProject(Map m, ContentType type) {
    final idx = (m['latestFilesIndexes'] as List? ?? []);
    return ContentProject(
      platform: ContentPlatform.curseforge,
      id: '${m['id']}',
      slug: '${m['slug']}',
      title: '${m['name']}',
      description: '${m['summary'] ?? ''}',
      author: '${(m['authors'] as List?)?.firstOrNull?['name'] ?? ''}',
      iconUrl: (m['logo'] as Map?)?['thumbnailUrl'] as String?,
      downloads: (m['downloadCount'] as num?)?.toInt() ?? 0,
      categories: [for (final c in (m['categories'] as List? ?? [])) '${c['name']}'],
      gameVersions: {for (final f in idx) '${f['gameVersion']}'}.toList(),
      loaders: {
        for (final f in idx)
          if (f['modLoader'] != null) ?_cfLoader.entries.where((e) => e.value == f['modLoader']).firstOrNull?.key
      }.toList(),
      updated: DateTime.tryParse('${m['dateModified']}'),
      type: type,
    );
  }

  // ---------------- versions ----------------

  Future<List<ContentVersion>> versions(ContentProject p, {String? gameVersion, String? loader}) =>
      p.platform == ContentPlatform.modrinth ? mrVersions(p.id, gameVersion: gameVersion, loader: loader) : _cfVersions(p.id, gameVersion, loader);

  Future<List<ContentVersion>> mrVersions(String projectId, {String? gameVersion, String? loader}) async {
    final q = <String, String>{
      if (gameVersion != null && gameVersion.isNotEmpty) 'game_versions': '["$gameVersion"]',
      if (loader != null && loader.isNotEmpty) 'loaders': '["$loader"]',
    };
    final j = await _get(Uri.parse('$_mr/project/$projectId/version').replace(queryParameters: q.isEmpty ? null : q)) as List;
    return [for (final v in j) _mrVersion(v as Map)];
  }

  Future<ContentVersion> mrVersion(String versionId) async => _mrVersion(await _get(Uri.parse('$_mr/version/$versionId')) as Map);

  /// Looks up installed files by SHA1 (for "检查更新" and identifying local mods).
  Future<Map<String, ContentVersion>> mrVersionsByHash(List<String> sha1s) async {
    if (sha1s.isEmpty) return {};
    final j = await http.postJson(Uri.parse('$_mr/version_files'), {'hashes': sha1s, 'algorithm': 'sha1'}) as Map;
    return {for (final e in j.entries) '${e.key}': _mrVersion(e.value as Map)};
  }

  Future<ContentProject> mrProject(String idOrSlug) async {
    final h = await _get(Uri.parse('$_mr/project/$idOrSlug')) as Map;
    return ContentProject(
      platform: ContentPlatform.modrinth,
      id: '${h['id']}',
      slug: '${h['slug']}',
      title: '${h['title']}',
      description: '${h['description'] ?? ''}',
      author: '',
      iconUrl: h['icon_url'] as String?,
      downloads: (h['downloads'] as num?)?.toInt() ?? 0,
      categories: [for (final c in (h['categories'] as List? ?? [])) '$c'],
      gameVersions: [for (final c in (h['game_versions'] as List? ?? [])) '$c'],
      loaders: [for (final c in (h['loaders'] as List? ?? [])) '$c'],
      updated: DateTime.tryParse('${h['updated']}'),
      type: ContentType.values.firstWhere((t) => t.modrinth == h['project_type'], orElse: () => ContentType.mod),
    );
  }

  ContentVersion _mrVersion(Map v) => ContentVersion(
        platform: ContentPlatform.modrinth,
        id: '${v['id']}',
        projectId: '${v['project_id']}',
        name: '${v['name']}',
        versionNumber: '${v['version_number']}',
        gameVersions: [for (final g in v['game_versions'] as List? ?? []) '$g'],
        loaders: [for (final g in v['loaders'] as List? ?? []) '$g'],
        channel: '${v['version_type'] ?? 'release'}',
        published: DateTime.tryParse('${v['date_published']}') ?? DateTime(2000),
        files: [
          for (final f in v['files'] as List? ?? [])
            ContentFile('${f['url']}', '${f['filename']}', (f['hashes'] as Map?)?['sha1'] as String?, (f['size'] as num?)?.toInt() ?? 0,
                f['primary'] == true)
        ],
        dependencies: [
          for (final d in v['dependencies'] as List? ?? [])
            if (d['project_id'] != null) Dependency('${d['project_id']}', d['version_id'] as String?, d['dependency_type'] == 'required')
        ],
        downloads: (v['downloads'] as num?)?.toInt() ?? 0,
      );

  Future<List<ContentVersion>> _cfVersions(String modId, String? gv, String? loader) async {
    final q = <String, String>{
      'pageSize': '50',
      if (gv != null && gv.isNotEmpty) 'gameVersion': gv,
      if (loader != null && _cfLoader[loader] != null) 'modLoaderType': '${_cfLoader[loader]}',
    };
    final j = await _get(Uri.parse('$_cf/mods/$modId/files').replace(queryParameters: q), headers: _cfHeaders) as Map;
    return [for (final f in j['data'] as List) cfFile(f as Map)];
  }

  Future<ContentVersion> cfFileById(int modId, int fileId) async =>
      cfFile((await _get(Uri.parse('$_cf/mods/$modId/files/$fileId'), headers: _cfHeaders) as Map)['data'] as Map);

  /// Batch file lookup (modpack install).
  Future<List<ContentVersion>> cfFiles(List<int> fileIds) async {
    final j = await http.postJson(Uri.parse('$_cf/mods/files'), {'fileIds': fileIds}, headers: _cfHeaders) as Map;
    return [for (final f in j['data'] as List) cfFile(f as Map)];
  }

  /// Newest compatible Modrinth version for each installed file hash.
  Future<Map<String, ContentVersion>> mrLatestByHash(List<String> sha1s, {required String gameVersion, String? loader}) async {
    if (sha1s.isEmpty) return {};
    final j = await http.postJson(Uri.parse('$_mr/version_files/update'), {
      'hashes': sha1s,
      'algorithm': 'sha1',
      if (loader != null && loader.isNotEmpty) 'loaders': [loader],
      'game_versions': [gameVersion],
    }) as Map;
    return {for (final e in j.entries) '${e.key}': _mrVersion(e.value as Map)};
  }

  /// CurseForge fingerprint matches → (fingerprint, installed file).
  Future<List<(int, ContentVersion)>> cfMatchFingerprints(List<int> fingerprints) async {
    if (fingerprints.isEmpty) return [];
    final j = await http.postJson(Uri.parse('$_cf/fingerprints/432'), {'fingerprints': fingerprints}, headers: _cfHeaders) as Map;
    final data = j['data'] as Map? ?? const {};
    return [
      for (final m in data['exactMatches'] as List? ?? [])
        ((m['file']['fileFingerprint'] as num).toInt(), cfFile(m['file'] as Map))
    ];
  }

  /// All files of a CurseForge project for a game version / loader.
  Future<List<ContentVersion>> cfModFiles(String modId, {String? gameVersion, String? loader}) => _cfVersions(modId, gameVersion, loader);

  ContentVersion cfFile(Map f) {
    final gvs = [for (final g in f['gameVersions'] as List? ?? []) '$g'];
    final sha1 = (f['hashes'] as List? ?? []).where((h) => h['algo'] == 1).map((h) => '${h['value']}').firstOrNull;
    final id = (f['id'] as num).toInt();
    final name = '${f['fileName']}';
    // some authors disable third-party distribution: downloadUrl is null → rebuild the CDN URL
    final url = (f['downloadUrl'] as String?) ?? 'https://edge.forgecdn.net/files/${id ~/ 1000}/${id % 1000}/${Uri.encodeComponent(name)}';
    return ContentVersion(
      platform: ContentPlatform.curseforge,
      id: '$id',
      projectId: '${f['modId']}',
      name: '${f['displayName']}',
      versionNumber: '${f['displayName']}',
      gameVersions: gvs.where((g) => RegExp(r'^\d').hasMatch(g)).toList(),
      loaders: gvs.map((g) => g.toLowerCase()).where(_cfLoader.containsKey).toList(),
      channel: switch (f['releaseType']) { 2 => 'beta', 3 => 'alpha', _ => 'release' },
      published: DateTime.tryParse('${f['fileDate']}') ?? DateTime(2000),
      files: [ContentFile(url, name, sha1, (f['fileLength'] as num?)?.toInt() ?? 0, true)],
      dependencies: [
        for (final d in f['dependencies'] as List? ?? []) Dependency('${d['modId']}', null, d['relationType'] == 3)
      ],
      downloads: (f['downloadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<dynamic> _get(Uri u, {Map<String, String>? headers}) async {
    try {
      return await http.getJson(u, headers: headers);
    } on HttpStatusException catch (e) {
      if (e.status == 403 && u.host == 'api.curseforge.com') {
        throw CmlException('cf_key', 'CurseForge 官方 API 需要 API Key，请在设置中填写，或改用 MCIM 镜像', e);
      }
      rethrow;
    }
  }
}
