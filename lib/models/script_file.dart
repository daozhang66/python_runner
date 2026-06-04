class ScriptFile {
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int runCount;
  final bool isPinned;
  final int sortOrder;
  final int? groupId;

  ScriptFile({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    this.runCount = 0,
    this.isPinned = false,
    this.sortOrder = 0,
    this.groupId,
  });

  ScriptFile copyWith({
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? runCount,
    bool? isPinned,
    int? sortOrder,
    int? groupId,
    bool clearGroup = false,
  }) {
    return ScriptFile(
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      runCount: runCount ?? this.runCount,
      isPinned: isPinned ?? this.isPinned,
      sortOrder: sortOrder ?? this.sortOrder,
      groupId: clearGroup ? null : groupId ?? this.groupId,
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
      'sortOrder': sortOrder,
      'groupId': groupId,
    };
  }

  factory ScriptFile.fromMap(Map<String, dynamic> map) {
    return ScriptFile(
      name: map['name'] as String,
      path: map['path'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num).toInt()),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modifiedAt'] as num).toInt()),
      runCount: map['runCount'] as int? ?? 0,
      isPinned: (map['isPinned'] as int? ?? 0) == 1,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
      groupId: (map['groupId'] as num?)?.toInt(),
    );
  }
}
