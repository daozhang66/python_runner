import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/pigeon/native_runtime_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/daozhang/py/NativeRuntimeApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.daozhang.py'),
    dartPackageName: 'python_runner',
  ),
)
class LinuxLikeRuntimeInfo {
  LinuxLikeRuntimeInfo({
    required this.available,
    required this.installed,
    required this.message,
    required this.pythonPath,
    required this.pipPath,
    required this.rootfsDir,
  });

  bool available;
  bool installed;
  String message;
  String pythonPath;
  String pipPath;
  String rootfsDir;
}

class NativeAppFileEntry {
  NativeAppFileEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modifiedAtMillis,
  });

  String path;
  String name;
  bool isDirectory;
  int size;
  int modifiedAtMillis;
}

class NativePythonInfo {
  NativePythonInfo({
    required this.pythonVersion,
    required this.sitePackages,
    required this.pythonPath,
    required this.chaquopyPipDir,
  });

  String pythonVersion;
  String sitePackages;
  String pythonPath;
  String chaquopyPipDir;
}

class NativeAppInfo {
  NativeAppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  String appName;
  String packageName;
  String version;
  String buildNumber;
}

@HostApi()
abstract class RuntimeHostApi {
  LinuxLikeRuntimeInfo getLinuxLikeRuntimeInfo();

  @async
  NativePythonInfo getPythonInfo();
}

@HostApi()
abstract class FilePickerHostApi {
  List<NativeAppFileEntry> getFilePickerRoots();
  List<NativeAppFileEntry> listFilePickerDirectory(String path);
  Uint8List readFilePickerFile(String path);
}

@HostApi()
abstract class AppHostApi {
  NativeAppInfo getAppInfo();
  bool checkOverlayPermission();
  String? consumePendingRunScript();
}
