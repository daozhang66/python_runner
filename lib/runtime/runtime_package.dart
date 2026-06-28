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
  final String integrityStatus;
  final String integrityMessage;
  final List<String> missingImports;

  const RuntimePackage({
    required this.name,
    required this.version,
    this.source = '',
    this.integrityStatus = 'unknown',
    this.integrityMessage = '',
    this.missingImports = const [],
  });

  factory RuntimePackage.fromMap(Map<String, dynamic> map) {
    return RuntimePackage(
      name: map['name']?.toString() ?? '',
      version: map['version']?.toString() ?? '',
      source: map['source']?.toString() ?? '',
      integrityStatus: map['integrityStatus']?.toString() ?? 'unknown',
      integrityMessage: map['integrityMessage']?.toString() ?? '',
      missingImports: _stringListFromDynamic(map['missingImports']),
    );
  }

  bool get isUserPackage => source == 'user';

  bool get hasBrokenIntegrity => integrityStatus == 'broken';
}

List<String> _stringListFromDynamic(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  return const [];
}
