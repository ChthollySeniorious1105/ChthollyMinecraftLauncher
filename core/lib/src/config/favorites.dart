import 'package:path/path.dart' as p;

import '../common/json_file.dart';
import '../common/os.dart';

/// A named favourites folder ("收藏夹") holding versions from any game directory.
class FavoriteFolder {
  String name;

  /// Material icon code point chosen by the user.
  int icon;

  /// ARGB colour.
  int color;

  /// Entries are `gameDir|versionId` so the same id in different .minecraft folders stays distinct.
  final List<String> entries;
  FavoriteFolder(this.name, {this.icon = 0xf01d4, this.color = 0xFFFFB300, List<String>? entries}) : entries = entries ?? [];

  Map<String, dynamic> toJson() => {'name': name, 'icon': icon, 'color': color, 'entries': entries};
  factory FavoriteFolder.fromJson(Map j) =>
      FavoriteFolder('${j['name']}', icon: (j['icon'] as num?)?.toInt() ?? 0xf01d4, color: (j['color'] as num?)?.toInt() ?? 0xFFFFB300, entries: [for (final e in j['entries'] as List? ?? []) '$e']);
}

/// Version favourites: a default "收藏" folder plus user folders. Persisted in `%APPDATA%\CML\favorites.json`.
class Favorites {
  final String path;
  final List<FavoriteFolder> folders = [];
  Favorites([String? path]) : path = path ?? p.join(Os.cmlHome, 'favorites.json');

  static String key(String gameDir, String versionId) => '${p.normalize(gameDir).toLowerCase()}|$versionId';
  static (String, String) parse(String key) {
    final i = key.lastIndexOf('|');
    return (key.substring(0, i), key.substring(i + 1));
  }

  FavoriteFolder get defaultFolder => folders.first;

  Future<void> load() async {
    folders.clear();
    final j = await JsonFile.read(path);
    if (j is Map) {
      for (final f in j['folders'] as List? ?? []) {
        folders.add(FavoriteFolder.fromJson(f as Map));
      }
    }
    if (folders.isEmpty) folders.add(FavoriteFolder('收藏'));
  }

  Future<void> save() => JsonFile.write(path, {'folders': [for (final f in folders) f.toJson()]});

  bool isFavorite(String gameDir, String id) => folders.any((f) => f.entries.contains(key(gameDir, id)));
  List<FavoriteFolder> foldersOf(String gameDir, String id) => [for (final f in folders) if (f.entries.contains(key(gameDir, id))) f];

  Future<void> toggle(String gameDir, String id, [FavoriteFolder? folder]) async {
    final f = folder ?? defaultFolder;
    final k = key(gameDir, id);
    f.entries.contains(k) ? f.entries.remove(k) : f.entries.add(k);
    await save();
  }

  Future<void> setFolders(String gameDir, String id, Set<FavoriteFolder> selected) async {
    final k = key(gameDir, id);
    for (final f in folders) {
      if (selected.contains(f)) {
        if (!f.entries.contains(k)) f.entries.add(k);
      } else {
        f.entries.remove(k);
      }
    }
    await save();
  }

  Future<FavoriteFolder> addFolder(String name, {int? icon, int? color}) async {
    final f = FavoriteFolder(name, icon: icon ?? 0xf77e, color: color ?? 0xFF42A5F5);
    folders.add(f);
    await save();
    return f;
  }

  Future<void> removeFolder(FavoriteFolder f) async {
    if (identical(f, defaultFolder)) return;
    folders.remove(f);
    await save();
  }

  Future<void> move(FavoriteFolder f, int newIndex) async {
    folders.remove(f);
    folders.insert(newIndex.clamp(1, folders.length), f);
    await save();
  }

  /// Keeps favourites pointing at the right id after a version is renamed / deleted.
  Future<void> onRenamed(String gameDir, String from, String to) async {
    final a = key(gameDir, from), b = key(gameDir, to);
    for (final f in folders) {
      final i = f.entries.indexOf(a);
      if (i >= 0) f.entries[i] = b;
    }
    await save();
  }

  Future<void> onDeleted(String gameDir, String id) async {
    final k = key(gameDir, id);
    for (final f in folders) {
      f.entries.remove(k);
    }
    await save();
  }
}
