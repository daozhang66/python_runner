enum PackageStatus { installed, installing, uninstalling, error }

class PackageInfo {
  final String name;
  final String version;
  final PackageStatus status;
  final bool isUserPackage;

  PackageInfo({
    required this.name,
    this.version = '',
    this.status = PackageStatus.installed,
    this.isUserPackage = false,
  });

  PackageInfo copyWith({String? name, String? version, PackageStatus? status, bool? isUserPackage}) {
    return PackageInfo(
      name: name ?? this.name,
      version: version ?? this.version,
      status: status ?? this.status,
      isUserPackage: isUserPackage ?? this.isUserPackage,
    );
  }
}
