import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

import '../state.dart';

/// Star toggle for a version. Click = add/remove from the default folder; right-click / long-press = choose folders.
class FavoriteStar extends StatelessWidget {
  final String gameDir;
  final String versionId;
  final double size;
  final Color? color;
  const FavoriteStar({super.key, required this.gameDir, required this.versionId, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final fav = app.ctx.favorites;
    final on = fav.isFavorite(gameDir, versionId);
    return GestureDetector(
      onSecondaryTap: () => showFavoriteFolders(context, gameDir, versionId),
      onLongPress: () => showFavoriteFolders(context, gameDir, versionId),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: on ? trGlobal('已收藏（右键选择收藏夹）') : trGlobal('收藏（右键选择收藏夹）'),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded,
              key: ValueKey(on), size: size, color: on ? const Color(0xFFFFB300) : (color ?? Theme.of(context).hintColor)),
        ),
        onPressed: () async {
          if (on && fav.foldersOf(gameDir, versionId).length > 1) {
            await showFavoriteFolders(context, gameDir, versionId);
            return;
          }
          await fav.toggle(gameDir, versionId);
          app.changed();
        },
      ),
    );
  }
}

/// Lets the user tick which folders contain a version, and create folders.
Future<void> showFavoriteFolders(BuildContext context, String gameDir, String versionId) =>
    showDialog(context: context, builder: (_) => _FolderPicker(gameDir: gameDir, versionId: versionId));

class _FolderPicker extends StatefulWidget {
  final String gameDir, versionId;
  const _FolderPicker({required this.gameDir, required this.versionId});
  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  late Set<FavoriteFolder> selected = App.read(context).ctx.favorites.foldersOf(widget.gameDir, widget.versionId).toSet();

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final fav = app.ctx.favorites;
    return AlertDialog(
      title: Text(trGlobal('收藏 {0}', [widget.versionId])),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in fav.folders)
            CheckboxListTile(
              value: selected.contains(f),
              secondary: Icon(favoriteIcon(f), color: Color(f.color)),
              title: Text(favoriteName(f)),
              subtitle: Text(trGlobal('{0} 个版本', [f.entries.length])),
              onChanged: (v) => setState(() => v == true ? selected.add(f) : selected.remove(f)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(trGlobal('新建收藏夹')),
            onTap: () async {
              final f = await editFavoriteFolder(context);
              if (f != null) setState(() => selected.add(f));
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('取消'))),
        FilledButton(
          onPressed: () async {
            await fav.setFolders(widget.gameDir, widget.versionId, selected);
            app.changed();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(trGlobal('保存')),
        ),
      ],
    );
  }
}

/// Icon of a folder (stored as a code point; resolved against the fixed list so icon tree-shaking stays valid).
IconData favoriteIcon(FavoriteFolder f) => favoriteIcons.firstWhere((i) => i.codePoint == f.icon, orElse: () => Icons.folder_rounded);

const favoriteIcons = <IconData>[
  Icons.star_rounded, Icons.folder_rounded, Icons.favorite_rounded, Icons.bolt_rounded, Icons.extension_rounded, Icons.sports_esports_rounded,
  Icons.build_rounded, Icons.public_rounded, Icons.groups_rounded, Icons.science_rounded, Icons.auto_awesome_rounded, Icons.local_fire_department_rounded,
];
const favoriteColors = <Color>[
  Color(0xFFFFB300), Color(0xFFEF5350), Color(0xFFEC407A), Color(0xFFAB47BC), Color(0xFF5C6BC0), Color(0xFF42A5F5),
  Color(0xFF26A69A), Color(0xFF66BB6A), Color(0xFF8D6E63), Color(0xFF78909C),
];

/// Create (folder == null) or edit a favourites folder. Returns the folder.
Future<FavoriteFolder?> editFavoriteFolder(BuildContext context, {FavoriteFolder? folder}) async {
  final app = App.read(context);
  final name = TextEditingController(text: folder?.name ?? '');
  var icon = folder?.icon ?? favoriteIcons[1].codePoint;
  var color = folder?.color ?? favoriteColors[5].toARGB32();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(folder == null ? trGlobal('新建收藏夹') : trGlobal('编辑收藏夹')),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: trGlobal('名称'), hintText: trGlobal('例如：生存、模组整合、PVP'))),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final i in favoriteIcons)
                ChoiceChip(
                  label: Icon(i, size: 18, color: Color(color)),
                  selected: icon == i.codePoint,
                  showCheckmark: false,
                  onSelected: (_) => set(() => icon = i.codePoint),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final col in favoriteColors)
                GestureDetector(
                  onTap: () => set(() => color = col.toARGB32()),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(color: color == col.toARGB32() ? Theme.of(c).colorScheme.onSurface : Colors.transparent, width: 2),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(trGlobal('取消'))),
          FilledButton(onPressed: () => Navigator.pop(c, name.text.trim().isNotEmpty), child: Text(trGlobal('确定'))),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final fav = app.ctx.favorites;
  if (folder == null) {
    final f = await fav.addFolder(name.text.trim(), icon: icon, color: color);
    app.changed();
    return f;
  }
  folder
    ..name = name.text.trim()
    ..icon = icon
    ..color = color;
  await fav.save();
  app.changed();
  return folder;
}

/// Display name: the built-in default folder ("收藏") follows the UI language until the user renames it.
String favoriteName(FavoriteFolder f) => f.name == '收藏' ? trGlobal('收藏') : f.name;
