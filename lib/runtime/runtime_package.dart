class PackageInstallRequest {
  final String packageName;
  final String? version;
  final String? indexUrl;

  const PackageInstallRequest({
    required this.packageName,
    this.version,
    this.indexUrl,
  });
}

class RequirementsInstallRequest {
  final String? projectKey;
  final String requirementsPath;
  final String? content;
  final String displayName;
  final String? indexUrl;

  const RequirementsInstallRequest({
    this.projectKey,
    this.requirementsPath = 'requirements.txt',
    this.content,
    this.displayName = 'requirements.txt',
    this.indexUrl,
  });
}

class PackageInstallResult {
  final bool success;
  final String message;

  const PackageInstallResult({
    required this.success,
    this.message = '',
  });
}

class PackageUninstallResult {
  final bool success;
  final String message;
  final List<String> removedDependencies;

  const PackageUninstallResult({
    required this.success,
    this.message = '',
    this.removedDependencies = const [],
  });

  factory PackageUninstallResult.fromMap(Map<String, dynamic> map) {
    final rawRemovedDependencies = map['removedDependencies'];
    final removedDependencies = rawRemovedDependencies is List
        ? rawRemovedDependencies.map((item) => item.toString()).toList()
        : const <String>[];
    return PackageUninstallResult(
      success: map['success'] == true,
      message: map['message']?.toString() ?? '',
      removedDependencies: removedDependencies,
    );
  }

  bool get cleanedOrphanDependencies => removedDependencies.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'message': message,
      'removedDependencies': removedDependencies,
    };
  }
}

class PackageInstallProgress {
  final String status;
  final String message;

  const PackageInstallProgress({
    required this.status,
    required this.message,
  });

  factory PackageInstallProgress.fromMap(Map<dynamic, dynamic> map) {
    return PackageInstallProgress(
      status: map['status']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
    );
  }
}

class RuntimePackage {
  final String name;
  final String version;
  final String source;

  const RuntimePackage({
    required this.name,
    required this.version,
    this.source = '',
  });

  bool get isUserPackage => source == 'user';
}
