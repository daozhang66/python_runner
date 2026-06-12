import 'dart:convert';
import 'dart:io';

final RegExp _sha256Pattern = RegExp(r'\b[a-fA-F0-9]{64}\b');

String? _extractSha256(String? text) {
  if (text == null) return null;
  final match = _sha256Pattern.firstMatch(text);
  return match?.group(0)?.toLowerCase();
}

class ReleaseAssetInfo {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;
  final String? sha256;
  final String? checksumDownloadUrl;

  const ReleaseAssetInfo({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
    this.sha256,
    this.checksumDownloadUrl,
  });

  factory ReleaseAssetInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseAssetInfo(
      name: json['name']?.toString() ?? '',
      downloadUrl: json['browser_download_url']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type']?.toString() ?? '',
      sha256: _extractSha256(
        json['sha256']?.toString() ?? json['digest']?.toString(),
      ),
    );
  }

  bool get isApk => name.toLowerCase().endsWith('.apk');

  ReleaseAssetInfo copyWith({
    String? sha256,
    String? checksumDownloadUrl,
  }) {
    return ReleaseAssetInfo(
      name: name,
      downloadUrl: downloadUrl,
      size: size,
      contentType: contentType,
      sha256: sha256 ?? this.sha256,
      checksumDownloadUrl: checksumDownloadUrl ?? this.checksumDownloadUrl,
    );
  }
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseName;
  final String releaseNotes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final ReleaseAssetInfo? apkAsset;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseName,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.apkAsset,
  });

  bool get hasUpdate =>
      UpdateService.compareVersions(latestVersion, currentVersion) > 0;

  AppUpdateInfo copyWith({ReleaseAssetInfo? apkAsset}) {
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      tagName: tagName,
      releaseName: releaseName,
      releaseNotes: releaseNotes,
      htmlUrl: htmlUrl,
      publishedAt: publishedAt,
      apkAsset: apkAsset ?? this.apkAsset,
    );
  }
}

class ReleaseLogEntry {
  final String tagName;
  final String version;
  final String releaseName;
  final String releaseNotes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final bool isPrerelease;
  final ReleaseAssetInfo? apkAsset;

  const ReleaseLogEntry({
    required this.tagName,
    required this.version,
    required this.releaseName,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isPrerelease,
    required this.apkAsset,
  });

  factory ReleaseLogEntry.fromJson(Map<String, dynamic> json) {
    final assets = ((json['assets'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ReleaseAssetInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    ReleaseAssetInfo? apkAsset;
    for (final asset in assets) {
      if (asset.isApk) {
        apkAsset = asset;
        break;
      }
    }

    final tagName = json['tag_name']?.toString() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    return ReleaseLogEntry(
      tagName: tagName,
      version: UpdateService.normalizeVersion(tagName),
      releaseName: name.isEmpty ? tagName : name,
      releaseNotes: json['body']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      isPrerelease: json['prerelease'] == true,
      apkAsset: apkAsset,
    );
  }

  bool get hasReleaseNotes => releaseNotes.trim().isNotEmpty;
}

class UpdateService {
  static const String _owner = 'daozhang66';
  static const String _repo = 'python_runner';
  static const String _apiVersion = '2022-11-28';

  Future<AppUpdateInfo> fetchLatestRelease({
    required String currentVersion,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
      );
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers
          .set(HttpHeaders.userAgentHeader, 'python_runner/$currentVersion');
      request.headers.set('X-GitHub-Api-Version', _apiVersion);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        final apiMessage = extractApiErrorMessage(body);
        throw HttpException(
          apiMessage == null
              ? 'Update API failed: ${response.statusCode}'
              : 'Update API failed: ${response.statusCode} ($apiMessage)',
          uri: request.uri,
        );
      }

      final updateInfo = parseLatestReleaseResponse(
        body: body,
        currentVersion: currentVersion,
      );
      return _resolveChecksumAsset(
        client: client,
        updateInfo: updateInfo,
        currentVersion: currentVersion,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AppUpdateInfo> _resolveChecksumAsset({
    required HttpClient client,
    required AppUpdateInfo updateInfo,
    required String currentVersion,
  }) async {
    final asset = updateInfo.apkAsset;
    if (asset == null ||
        asset.sha256 != null ||
        asset.checksumDownloadUrl == null ||
        asset.checksumDownloadUrl!.isEmpty) {
      return updateInfo;
    }

    try {
      final checksum = await _fetchChecksum(
        client: client,
        url: asset.checksumDownloadUrl!,
        currentVersion: currentVersion,
      );
      return updateInfo.copyWith(apkAsset: asset.copyWith(sha256: checksum));
    } catch (_) {
      // Keep the update visible but leave sha256 empty so auto-install is blocked.
      return updateInfo;
    }
  }

  Future<String> _fetchChecksum({
    required HttpClient client,
    required String url,
    required String currentVersion,
  }) async {
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'text/plain,*/*');
    request.headers
        .set(HttpHeaders.userAgentHeader, 'python_runner/$currentVersion');

    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 64 * 1024) {
        throw const FormatException('Checksum asset is too large');
      }
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Checksum download failed: ${response.statusCode}',
        uri: uri,
      );
    }
    final checksum = extractSha256Checksum(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (checksum == null) {
      throw const FormatException('Checksum asset does not contain SHA-256');
    }
    return checksum;
  }

  Future<List<ReleaseLogEntry>> fetchReleaseLogs({int limit = 20}) async {
    final normalizedLimit = limit.clamp(1, 100).toInt();
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https(
          'api.github.com',
          '/repos/$_owner/$_repo/releases',
          {'per_page': '$normalizedLimit'},
        ),
      );
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'python_runner');
      request.headers.set('X-GitHub-Api-Version', _apiVersion);

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        final apiMessage = extractApiErrorMessage(body);
        throw HttpException(
          apiMessage == null
              ? 'Release log API failed: ${response.statusCode}'
              : 'Release log API failed: ${response.statusCode} ($apiMessage)',
          uri: request.uri,
        );
      }

      return parseReleaseLogsResponse(
        body: body,
        limit: normalizedLimit,
      );
    } finally {
      client.close(force: true);
    }
  }

  static AppUpdateInfo parseLatestReleaseResponse({
    required String body,
    required String currentVersion,
  }) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final assets = ((json['assets'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ReleaseAssetInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    ReleaseAssetInfo? apkAsset;
    for (final asset in assets) {
      if (asset.isApk) {
        apkAsset = asset;
        break;
      }
    }

    if (apkAsset != null) {
      final checksumName = '${apkAsset.name}.sha256';
      for (final asset in assets) {
        if (asset.name == checksumName) {
          apkAsset = apkAsset!.copyWith(
            checksumDownloadUrl: asset.downloadUrl,
          );
          break;
        }
      }
    }

    final tagName = json['tag_name']?.toString() ?? '';
    return AppUpdateInfo(
      currentVersion: normalizeVersion(currentVersion),
      latestVersion: normalizeVersion(tagName),
      tagName: tagName,
      releaseName: json['name']?.toString() ?? tagName,
      releaseNotes: json['body']?.toString() ?? '',
      htmlUrl: json['html_url']?.toString() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      apkAsset: apkAsset,
    );
  }

  static List<ReleaseLogEntry> parseReleaseLogsResponse({
    required String body,
    int limit = 20,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Release logs response must be a list');
    }

    final normalizedLimit = limit.clamp(1, 100).toInt();
    return decoded
        .whereType<Map>()
        .take(normalizedLimit)
        .map((e) => ReleaseLogEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static String normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '0.0.0';
    value = value.replaceFirst(RegExp(r'^[Vv]'), '');
    value = value.split('+').first;
    final match = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(value);
    return match?.group(1) ?? value;
  }

  static int compareVersions(String left, String right) {
    final a = normalizeVersion(left).split('.').map(int.tryParse).toList();
    final b = normalizeVersion(right).split('.').map(int.tryParse).toList();
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final ai = i < a.length ? (a[i] ?? 0) : 0;
      final bi = i < b.length ? (b[i] ?? 0) : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  static String? extractApiErrorMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final message = json['message']?.toString().trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? extractSha256Checksum(String body) => _extractSha256(body);
}
