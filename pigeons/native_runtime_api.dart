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

@HostApi()
abstract class RuntimeHostApi {
  LinuxLikeRuntimeInfo getLinuxLikeRuntimeInfo();
}

@HostApi()
abstract class FilePickerHostApi {
  List<NativeAppFileEntry> getFilePickerRoots();
  List<NativeAppFileEntry> listFilePickerDirectory(String path);
  Uint8List readFilePickerFile(String path);
}
