import '../../../models/script_file.dart';
import '../../../models/script_group.dart';

/// A root workspace entry. Group IDs cannot collide with valid script filenames.
class ScriptHomeItem {
  const ScriptHomeItem.script(ScriptFile value)
      : script = value,
        group = null;
  const ScriptHomeItem.group(ScriptGroup value)
      : group = value,
        script = null;

  final ScriptFile? script;
  final ScriptGroup? group;

  String get key => script?.name ?? 'group:${group!.id}';
  bool get isPinned => script?.isPinned ?? false;
  int? get homeSortOrder => script?.homeSortOrder ?? group?.homeSortOrder;
  DateTime get modifiedAt => script?.modifiedAt ?? group!.modifiedAt;
  int get sortOrder => script?.sortOrder ?? group!.sortOrder;

  static List<ScriptHomeItem> ordered(
      Iterable<ScriptFile> scripts, Iterable<ScriptGroup> groups) {
    final roots = scripts.where((s) => s.groupId == null).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final pinned = roots.where((s) => s.isPinned).map(ScriptHomeItem.script);
    final regular =
        roots.where((s) => !s.isPinned).map(ScriptHomeItem.script).toList();
    final folders = groups
        .where((g) => !g.isProject)
        .map(ScriptHomeItem.group)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final recent = [
      ...regular,
      ...groups.where((g) => g.isProject).map(ScriptHomeItem.group),
    ]..sort((a, b) {
        final time = b.modifiedAt.compareTo(a.modifiedAt);
        if (time != 0) return time;
        if ((a.group != null) != (b.group != null)) {
          return a.group != null ? 1 : -1;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final slots = [...folders, ...recent];
    final fallbackOrder = {
      for (var i = 0; i < slots.length; i++) slots[i].key: i
    };
    slots.sort((a, b) {
      final ar = a.homeSortOrder;
      final br = b.homeSortOrder;
      if (ar != null && br != null && ar != br) return ar.compareTo(br);
      if ((ar != null) != (br != null)) return ar != null ? -1 : 1;
      return fallbackOrder[a.key]!.compareTo(fallbackOrder[b.key]!);
    });
    // Script slots follow the existing script ranking, including run-to-front.
    // Stored home ranks determine their positions relative to groups.
    var scriptIndex = 0;
    return [
      ...pinned,
      ...slots
          .map((item) => item.script == null ? item : regular[scriptIndex++]),
    ];
  }
}
