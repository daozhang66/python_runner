import 'dart:convert';
import 'dart:io';

class ReleaseAssetInfo {
  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  const ReleaseAssetInfo({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAssetInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseAssetInfo(
      name: json['name']?.toString() ?? '',
      downloadUrl: json['browser_download_url']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type']?.toString() ?? '',
    );
  }

  bool get isApk => name.toLowerCase().endsWith('.apk');
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

      return parseLatestReleaseResponse(
        body: body,
        currentVersion: currentVersion,
      );
    } finally {
      client.close(force: true);
    }
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
}
