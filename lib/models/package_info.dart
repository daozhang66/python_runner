enum PackageStatus { installed, installing, uninstalling, error }

class PackageInfo {
  final String name;
  final String version;
  final PackageStatus status;
  final bool isUserPackage;
  final String integrityStatus;
  final String integrityMessage;
  final List<String> missingImports;

  PackageInfo({
    required this.name,
    this.version = '',
    this.status = PackageStatus.installed,
    this.isUserPackage = false,
    this.integrityStatus = 'unknown',
    this.integrityMessage = '',
    this.missingImports = const [],
  });

  bool get hasBrokenIntegrity => integrityStatus == 'broken';

  PackageInfo copyWith(
      {String? name,
      String? version,
      PackageStatus? status,
      bool? isUserPackage,
      String? integrityStatus,
      String? integrityMessage,
      List<String>? missingImports}) {
    return PackageInfo(
      name: name ?? this.name,
      version: version ?? this.version,
      status: status ?? this.status,
      isUserPackage: isUserPackage ?? this.isUserPackage,
      integrityStatus: integrityStatus ?? this.integrityStatus,
      integrityMessage: integrityMessage ?? this.integrityMessage,
      missingImports: missingImports ?? this.missingImports,
    );
  }
}
