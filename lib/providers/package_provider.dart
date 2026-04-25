import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/package_info.dart';
import '../services/native_bridge.dart';

class PackageProvider extends ChangeNotifier {
  final NativeBridge _bridge;

  List<PackageInfo> _packages = [];
  bool _installing = false;
  final List<String> _installLog = [];
  StreamSubscription? _installSub;

  List<PackageInfo> get packages => _packages;
  bool get installing => _installing;
  List<String> get installLog => List.unmodifiable(_installLog);

  PackageProvider(this._bridge) {
    _listenInstallProgress();
  }

  void _listenInstallProgress() {
    _installSub = _bridge.installProgressStream.listen((data) {
      final status = data['status'] as String? ?? '';
      final message = data['message'] as String? ?? '';
      _installLog.add(message);

      if (status == 'success') {
        _installing = false;
        loadPackages();
        // Auto-clear install log after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          clearInstallLog();
        });
      } else if (status == 'error') {
        _installing = false;
        // Auto-clear install log after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          clearInstallLog();
        });
      }

      notifyListeners();
    }, onError: (e) {
      debugPrint('installProgress error: $e');
    });
  }

  static const _builtins = [
    'pip', 'setuptools', 'wheel',
    'aiohttp', 'requests', 'httpx', 'beautifulsoup4', 'pyjwt',
    'certifi', 'urllib3', 'chardet',
    'ujson', 'marshmallow', 'python-dateutil', 'pytz',
    'pycryptodome', 'cffi', 'six', 'cryptography',
    'pyDes', 'rsa', 'pyasn1',
    'tinydb', 'peewee', 'pymysql', 'redis',
    'loguru', 'tqdm', 'openpyxl', 'python-docx',
    'numpy', 'pandas', 'pillow', 'lxml', 'sqlalchemy',
    'scipy', 'matplotlib', 'scikit-learn', 'opencv-python',
    'plyer', 'schedule',
  ];

  static String _norm(String n) => n.toLowerCase().replaceAll('-', '_');

  Future<void> loadPackages() async {
    try {
      final result = await _bridge.listInstalledPackages();
      final runtimePkgs = result.map((m) => PackageInfo(
        name: m['name'] ?? '',
        version: m['version'] ?? '',
      )).toList();
      final runtimeNames = runtimePkgs.map((p) => _norm(p.name)).toSet();
      final builtinPkgs = _builtins
          .where((n) => !runtimeNames.contains(_norm(n)))
          .map((n) => PackageInfo(name: n, version: 'built-in'));
      _packages = [...runtimePkgs, ...builtinPkgs];
      _packages.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    } catch (e) {
      debugPrint('loadPackages error: $e');
    }
  }

  Future<void> installPackage(String name, {String? version, String? indexUrl}) async {
    _installing = true;
    _installLog.clear();
    _installLog.add('Installing $name${version != null ? "==$version" : ""}...');
    notifyListeners();

    try {
      await _bridge.installPackage(name, version: version, indexUrl: indexUrl);
    } catch (e) {
      _installing = false;
      _installLog.add('Error: $e');
      notifyListeners();
    }
  }

  Future<bool> uninstallPackage(String name) async {
    // Immediately remove from local list for responsive UI
    _packages.removeWhere((p) => p.name == name);
    notifyListeners();

    try {
      await _bridge.uninstallPackage(name);
      // Native uninstall done, no need to reload — already removed from list
      return true;
    } catch (e) {
      debugPrint('uninstallPackage error: $e');
      // Restore actual state on error
      await loadPackages();
      return false;
    }
  }

  void clearInstallLog() {
    _installLog.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _installSub?.cancel();
    super.dispose();
  }
}
