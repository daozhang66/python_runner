class ScriptProjectFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  const ScriptProjectFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  factory ScriptProjectFile.fromMap(Map<dynamic, dynamic> map) {
    final path = map['path']?.toString() ?? '';
    return ScriptProjectFile(
      path: path,
      name: map['name']?.toString() ??
          (path.contains('/') ? path.split('/').last : path),
      isDirectory: map['isDirectory'] == true || map['isDirectory'] == 1,
      size: (map['size'] as num?)?.toInt() ?? 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['modifiedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'name': name,
      'isDirectory': isDirectory,
      'size': size,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
    };
  }
}
