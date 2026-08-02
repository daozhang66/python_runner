import '../../../models/script_file.dart';
import '../../../models/script_group.dart';

/// 脚本工作台不可变状态快照（Level 2）。
///
/// 与迁移前的 legacy ChangeNotifier 行为对齐：错误吞咽到 [AppLogger]，
/// [loadError] 仅作为扩展点暴露（现有 UI 不消费）；[generation] 用于防止
/// 旧加载请求覆盖新状态。脚本展示偏好（网格/平板选中）仍由
/// `scriptWorkspaceUiProvider` 管理，不并入业务 State。
class ScriptWorkspaceState {
  ScriptWorkspaceState({
    this.scripts = const [],
    this.groups = const [],
    this.isLoading = false,
    this.loadError,
    this.generation = 0,
    this.layoutRevision = 0,
  });

  /// 全部脚本（已按置顶 + sortOrder 排序）。集合不可变，外部不应直接修改。
  final List<ScriptFile> scripts;

  /// 全部分组（按 sortOrder 排序）。
  final List<ScriptGroup> groups;

  /// 是否正在加载（首次或刷新）。
  final bool isLoading;

  /// 加载失败的可展示错误文本；为 null 表示无错误。与 legacy 一致，当前 UI 不消费。
  final String? loadError;

  /// 加载代数，用于防止旧请求覆盖新状态。
  final int generation;

  /// Changes only when the list container needs a new arrangement. Metadata
  /// updates such as a script run count keep the existing layout selection.
  final int layoutRevision;

  /// 用于列表容器的结构快照。
  ///
  /// 脚本名称、分组、置顶状态和排序发生变化时才刷新 Sliver 容器；单个脚本的
  /// 运行次数或修改时间变化由卡片自身的 `select` 处理，避免重建整个工作台。
  late final ScriptWorkspaceLayout layout = ScriptWorkspaceLayout(
    scripts: scripts,
    groups: groups,
    isLoading: isLoading,
    revision: layoutRevision,
  );

  ScriptFile? scriptByName(String name) {
    for (final script in scripts) {
      if (script.name == name) return script;
    }
    return null;
  }

  ScriptGroup? groupById(int? id) {
    if (id == null) return null;
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  ScriptWorkspaceState copyWith({
    List<ScriptFile>? scripts,
    List<ScriptGroup>? groups,
    bool? isLoading,
    String? loadError,
    bool clearLoadError = false,
    int? generation,
    int? layoutRevision,
  }) {
    return ScriptWorkspaceState(
      scripts: scripts ?? this.scripts,
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      generation: generation ?? this.generation,
      layoutRevision: layoutRevision ?? this.layoutRevision,
    );
  }
}

/// 可按值比较的工作台结构快照。
class ScriptWorkspaceLayout {
  const ScriptWorkspaceLayout({
    required this.scripts,
    required this.groups,
    required this.isLoading,
    required this.revision,
  });

  final List<ScriptFile> scripts;
  final List<ScriptGroup> groups;
  final bool isLoading;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ScriptWorkspaceLayout &&
      other.revision == revision &&
      other.isLoading == isLoading;

  @override
  int get hashCode => Object.hash(revision, isLoading);
}
