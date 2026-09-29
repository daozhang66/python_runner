/// MCP 工具权限分组（计划 §8.1）。
///
/// 首期默认勾选只读权限，写入类（write_scripts / write_projects /
/// install_packages / run_scripts）默认关闭，开启后直接执行。
enum McpPermission {
  readScripts('read_scripts', 'read scripts', defaultEnabled: true),
  writeScripts('write_scripts', 'create or modify scripts',
      defaultEnabled: false),
  readProjects('read_projects', 'read projects', defaultEnabled: true),
  writeProjects('write_projects', 'create projects or modify project files',
      defaultEnabled: false),
  readNetwork('read_network', 'query network records', defaultEnabled: true),
  readPackages('read_packages', 'query installed packages',
      defaultEnabled: true),
  installPackages('install_packages', 'install packages',
      defaultEnabled: false),
  runScripts('run_scripts',
      'run scripts, send interactive input, read output, and stop',
      defaultEnabled: false),
  writeFilesystem(
      'write_filesystem', 'create directories, rename, or save files',
      defaultEnabled: false),
  deleteFilesystem('delete_filesystem', 'delete files or empty directories',
      defaultEnabled: false),
  readFilesystem('read_filesystem', 'read accessible files',
      defaultEnabled: true);

  const McpPermission(
    this.id,
    this.displayName, {
    required this.defaultEnabled,
  });

  final String id;
  final String displayName;
  final bool defaultEnabled;

  /// Mutating scopes are opt-in; calls execute without per-call dialogs.
  bool get isWriteScope =>
      this == writeScripts ||
      this == writeProjects ||
      this == installPackages ||
      this == runScripts ||
      this == writeFilesystem ||
      this == deleteFilesystem;

  static McpPermission? fromId(String id) {
    for (final permission in McpPermission.values) {
      if (permission.id == id) return permission;
    }
    return null;
  }

  /// 首期默认权限集合。
  static Set<McpPermission> get defaults {
    return {
      for (final permission in McpPermission.values)
        if (permission.defaultEnabled) permission,
    };
  }

  static Set<McpPermission> fromIds(Iterable<String> ids) {
    return {
      for (final id in ids) McpPermission.fromId(id),
    }.whereType<McpPermission>().toSet();
  }
}
