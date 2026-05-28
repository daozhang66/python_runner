class ScriptFile {
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int runCount;
  final bool isPinned;

  ScriptFile({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    this.runCount = 0,
    this.isPinned = false,
  });

  ScriptFile copyWith({
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? runCount,
    bool? isPinned,
  }) {
    return ScriptFile(
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      runCount: runCount ?? this.runCount,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'runCount': runCount,
      'isPinned': isPinned ? 1 : 0,
    };
  }

  factory ScriptFile.fromMap(Map<String, dynamic> map) {
    return ScriptFile(
      name: map['name'] as String,
      path: map['path'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modifiedAt'] as int),
      runCount: map['runCount'] as int? ?? 0,
      isPinned: (map['isPinned'] as int? ?? 0) == 1,
    );
  }
}
