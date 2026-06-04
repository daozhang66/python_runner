class ScriptGroup {
  final int? id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime modifiedAt;

  ScriptGroup({
    this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.modifiedAt,
  });

  ScriptGroup copyWith({
    int? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return ScriptGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
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
    );
  }
}
