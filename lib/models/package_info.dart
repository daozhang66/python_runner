enum PackageStatus { installed, installing, uninstalling, error }

class PackageInfo {
  final String name;
  final String version;
  final PackageStatus status;

  PackageInfo({
    required this.name,
    this.version = '',
    this.status = PackageStatus.installed,
  });

  PackageInfo copyWith({String? name, String? version, PackageStatus? status}) {
    return PackageInfo(
      name: name ?? this.name,
      version: version ?? this.version,
      status: status ?? this.status,
    );
  }
}
