class ScriptGroup {
  final int? id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? projectKey;
  final String? mainFilePath;
  final bool isProject;

  ScriptGroup({
    this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.modifiedAt,
    this.projectKey,
    this.mainFilePath,
    this.isProject = false,
  });

  ScriptGroup copyWith({
    int? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? projectKey,
    String? mainFilePath,
    bool? isProject,
    bool clearProjectKey = false,
    bool clearMainFilePath = false,
  }) {
    return ScriptGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      projectKey: clearProjectKey ? null : projectKey ?? this.projectKey,
      mainFilePath:
          clearMainFilePath ? null : mainFilePath ?? this.mainFilePath,
      isProject: isProject ?? this.isProject,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'projectKey': projectKey,
      'mainFilePath': mainFilePath,
      'isProject': isProject ? 1 : 0,
    };
  }

  factory ScriptGroup.fromMap(Map<String, dynamic> map) {
    return ScriptGroup(
      id: (map['id'] as num?)?.toInt(),
      name: map['name'] as String,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['createdAt'] as num).toInt()),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modifiedAt'] as num).toInt()),
      projectKey: map['projectKey'] as String?,
      mainFilePath: map['mainFilePath'] as String?,
      isProject: (map['isProject'] as num?)?.toInt() == 1,
    );
  }
}
