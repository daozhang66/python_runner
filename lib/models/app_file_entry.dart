class AppFileEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modifiedAt;

  const AppFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAt,
  });

  factory AppFileEntry.fromMap(Map<dynamic, dynamic> map) {
    final path = map['path']?.toString() ?? '';
    return AppFileEntry(
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
}

class AppFilePickResult {
  final String path;
  final String name;
  final bool useSystemPicker;

  const AppFilePickResult({
    required this.path,
    required this.name,
    this.useSystemPicker = false,
  });

  const AppFilePickResult.systemPicker()
      : path = '',
        name = '',
        useSystemPicker = true;
}
