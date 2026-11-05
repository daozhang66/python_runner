import 'package:shared_preferences/shared_preferences.dart';

/// Where the local shell starts. Null means "use the default" (the app's
/// private directory).
class LocalShellPrefs {
  const LocalShellPrefs._();

  static const String startDirKey = 'local_shell_start_dir';

  static Future<String?> loadStartDir() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(startDirKey)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// Saves [dir]; a null or blank value restores the default.
  static Future<void> saveStartDir(String? dir) async {
    final prefs = await SharedPreferences.getInstance();
    final value = dir?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(startDirKey);
    } else {
      await prefs.setString(startDirKey, value);
    }
  }

  /// The working directory scripts run in (Settings), if one is set.
  static Future<String?> loadScriptWorkingDir() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('working_dir')?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }
}
