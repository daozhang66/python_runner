import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:python_runner/features/backup/infrastructure/backup_config_store.dart';
import 'package:python_runner/features/backup/infrastructure/webdav_client.dart';

class MemorySecrets extends FlutterSecureStorage {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (fail) throw StateError('secure store locked');
    values[key] = value!;
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('profile is HTTPS, encodes path segments and rejects unsafe URLs', () {
    final config = WebDavConfig(
      baseUri: Uri.parse('https://dav.example/dav/'),
      username: 'me',
      remoteDirectory: '目录/100% space',
    );
    expect(
      config.folderUri.toString(),
      'https://dav.example/dav/%E7%9B%AE%E5%BD%95/100%25%20space/',
    );
    for (final url in [
      'http://dav.example',
      'https://user:pw@dav.example',
      'https://dav.example/?a=1',
      'https://dav.example/#secret',
    ]) {
      expect(
        () => WebDavConfig(baseUri: Uri.parse(url), username: 'me'),
        throwsFormatException,
      );
    }
  });
  test('failed secret replacement preserves prior usable profile; prefs contain no password', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = MemorySecrets();
    final store = BackupConfigStore(preferences: prefs, storage: secrets);
    final old = WebDavConfig(
      baseUri: Uri.parse('https://old.example'),
      username: 'old',
    );
    await store.saveProfile(old, password: 'original-secret');
    secrets.fail = true;
    await expectLater(
      store.saveProfile(
        WebDavConfig(
          baseUri: Uri.parse('https://new.example'),
          username: 'new',
        ),
        password: 'new-secret',
      ),
      throwsA(isA<BackupConfigurationException>()),
    );
    expect(store.loadProfile()!.baseUri.host, 'old.example');
    expect(await store.readPassword(), 'original-secret');
    expect(
      prefs.getKeys().map((k) => prefs.get(k)).join(),
      isNot(contains('secret')),
    );
    expect(secrets.values.keys.single, startsWith('backup_webdav.password.'));
    expect(BackupConfigStore.androidOptions.storageNamespace, 'backup_webdav');
    expect(BackupConfigStore.androidOptions.toMap()['resetOnError'], 'false');
  });
}
