import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

class WebDavConfig {
  WebDavConfig({
    required Uri baseUri,
    required this.username,
    String remoteDirectory = 'PythonRunner/Backups',
  }) : baseUri = _validateBase(baseUri),
       remoteDirectory = _validateDirectory(remoteDirectory) {
    if (username.contains(':') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(username)) {
      throw const FormatException('Invalid WebDAV username');
    }
  }
  final Uri baseUri;
  final String username;
  final String remoteDirectory;
  Uri get folderUri => baseUri.replace(
    pathSegments: [
      ...baseUri.pathSegments.where((p) => p.isNotEmpty),
      ...remoteDirectory.split('/'),
      '',
    ],
  );
  static Uri _validateBase(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.any(
          (s) => s == '.' || s == '..' || s.contains('/') || s.contains('\\'),
        )) {
      throw const FormatException(
        'Use an HTTPS WebDAV URL without credentials, query or fragment',
      );
    }
    return uri.replace(
      pathSegments: [...uri.pathSegments.where((p) => p.isNotEmpty), ''],
    );
  }

  static String _validateDirectory(String value) {
    final parts = value.split('/');
    if (parts.any(
      (p) =>
          p.isEmpty ||
          p == '.' ||
          p == '..' ||
          p.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(p),
    )) {
      throw const FormatException('Invalid WebDAV remote directory');
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
    'baseUri': baseUri.toString(),
    'username': username,
    'remoteDirectory': remoteDirectory,
  };
  @override
  String toString() => 'WebDavConfig(${baseUri.origin})';
}

/// A new override masks any inherited/global debug client and proxy settings.
class _VerifiedHttpOverrides extends HttpOverrides {}

HttpClient createVerifiedBackupHttpClient() =>
    HttpOverrides.runWithHttpOverrides(
      () => HttpClient()..findProxy = (_) => 'DIRECT',
      _VerifiedHttpOverrides(),
    );

class BackupCancelledException implements Exception {
  const BackupCancelledException();
  @override
  String toString() => 'Backup operation cancelled.';
}

class BackupCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const BackupCancelledException();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

enum WebDavErrorKind {
  authentication,
  permission,
  unsupported,
  notFound,
  conflict,
  network,
  timeout,
  invalidResponse,
}

class WebDavException implements Exception {
  const WebDavException(this.kind, {this.statusCode});
  final WebDavErrorKind kind;
  final int? statusCode;
  @override
  String toString() =>
      'WebDAV ${kind.name}${statusCode == null ? '' : ' (HTTP $statusCode)'}. Check the server settings and retry.';
}

class RemoteBackup {
  const RemoteBackup({
    required this.uri,
    required this.name,
    required this.size,
    this.modifiedAt,
  });
  final Uri uri;
  final String name;
  final int? size;
  final DateTime? modifiedAt;
}

typedef BackupTransferProgress = void Function(int completed, int? total);

class WebDavClient {
  WebDavClient({
    required this.config,
    required String password,
    HttpClient Function()? clientFactory,
  }) : _password = password,
       _clientFactory = clientFactory ?? createVerifiedBackupHttpClient;
  final WebDavConfig config;
  final String _password;
  final HttpClient Function() _clientFactory;
  static const connectionTimeout = Duration(seconds: 30);
  static const transferIdleTimeout = Duration(seconds: 60);
  static const maxXmlBytes = 8 * 1024 * 1024;

  bool _sameOrigin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == config.baseUri.host &&
      uri.port == config.baseUri.port &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
  Uri _child(String name) => config.folderUri.replace(
    pathSegments: [
      ...config.folderUri.pathSegments.where((s) => s.isNotEmpty),
      name,
    ],
  );
  bool _isBackupName(String name) =>
      name.startsWith('python-runner-backup-') &&
      name.endsWith('.zip') &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name);
  Uri? _validBackupUri(String href) {
    try {
      final uri = config.folderUri.resolve(href);
      if (!_sameOrigin(uri)) return null;
      final parent = config.folderUri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      final parts = uri.pathSegments;
      if (parts.length != parent.length + 1 || !_isBackupName(parts.last)) {
        return null;
      }
      for (var i = 0; i < parent.length; i++) {
        if (parent[i] != parts[i]) return null;
      }
      return uri;
    } catch (_) {
      return null;
    }
  }

  Future<T> _request<T>(
    String method,
    Uri uri, {
    required Set<int> accepted,
    required Future<T> Function(
      HttpClientResponse response,
      Stream<List<int>> body,
    )
    receive,
    Map<String, String> headers = const {},
    Stream<List<int>>? body,
    int? length,
    BackupCancellation? cancellation,
    BackupTransferProgress? onUpload,
  }) async {
    if (!_sameOrigin(uri)) {
      throw const WebDavException(WebDavErrorKind.invalidResponse);
    }
    cancellation?.check();
    final client = _clientFactory()..connectionTimeout = connectionTimeout;
    HttpClientRequest? request;
    Timer? idle;
    var timedOut = false;
    void resetIdle() {
      idle?.cancel();
      idle = Timer(transferIdleTimeout, () {
        timedOut = true;
        request?.abort();
        client.close(force: true);
      });
    }

    final unlisten = cancellation?.listen(() {
      request?.abort();
      client.close(force: true);
    });
    try {
      request = await client.openUrl(method, uri).timeout(connectionTimeout);
      cancellation?.check();
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${config.username}:$_password'))}',
      );
      headers.forEach(request.headers.set);
      if (length != null) request.contentLength = length;
      resetIdle();
      if (body != null) {
        var sent = 0;
        await request.addStream(
          body.map((chunk) {
            cancellation?.check();
            resetIdle();
            sent += chunk.length;
            onUpload?.call(sent, length);
            return chunk;
          }),
        );
      }
      final response = await request.close();
      cancellation?.check();
      if (!accepted.contains(response.statusCode)) {
        throw _statusError(response.statusCode);
      }
      final responseBody = response.map((chunk) {
        cancellation?.check();
        resetIdle();
        return chunk;
      });
      final result = await receive(response, responseBody);
      cancellation?.check();
      return result;
    } catch (error) {
      cancellation?.check();
      if (timedOut || error is TimeoutException) {
        throw const WebDavException(WebDavErrorKind.timeout);
      }
      if (error is WebDavException || error is BackupCancelledException) {
        rethrow;
      }
      throw const WebDavException(WebDavErrorKind.network);
    } finally {
      idle?.cancel();
      unlisten?.call();
      client.close(force: true);
    }
  }

  WebDavException _statusError(int status) => WebDavException(switch (status) {
    401 => WebDavErrorKind.authentication,
    403 => WebDavErrorKind.permission,
    404 => WebDavErrorKind.notFound,
    409 || 412 => WebDavErrorKind.conflict,
    301 ||
    302 ||
    303 ||
    307 ||
    308 ||
    405 ||
    501 => WebDavErrorKind.unsupported,
    _ => WebDavErrorKind.network,
  }, statusCode: status);

  Future<int> _empty(
    String method,
    Uri uri, {
    Set<int> accepted = const {200, 201, 204},
    Map<String, String> headers = const {},
    Stream<List<int>>? body,
    int? length,
    BackupCancellation? cancellation,
    BackupTransferProgress? onUpload,
  }) => _request(
    method,
    uri,
    accepted: accepted,
    headers: headers,
    body: body,
    length: length,
    cancellation: cancellation,
    onUpload: onUpload,
    receive: (response, body) async => response.statusCode,
  );

  Future<XmlDocument> _propfind(
    Uri uri,
    int depth,
    BackupCancellation? cancellation,
  ) => _request(
    'PROPFIND',
    uri,
    accepted: {207},
    headers: {
      'Depth': '$depth',
      'Content-Type': 'application/xml; charset=utf-8',
    },
    cancellation: cancellation,
    body: Stream.value(
      utf8.encode(
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>',
      ),
    ),
    receive: (_, body) async {
      final bytes = <int>[];
      await for (final chunk in body) {
        if (bytes.length + chunk.length > maxXmlBytes) {
          throw const WebDavException(WebDavErrorKind.invalidResponse);
        }
        bytes.addAll(chunk);
      }
      try {
        return XmlDocument.parse(utf8.decode(bytes));
      } catch (_) {
        throw const WebDavException(WebDavErrorKind.invalidResponse);
      }
    },
  );
  Iterable<XmlElement> _children(XmlNode node, String name) => node.children
      .whereType<XmlElement>()
      .where((e) => e.name.local == name && e.namespaceUri == 'DAV:');
  Iterable<XmlElement> _responses(XmlDocument document) {
    final root = document.rootElement;
    if (root.name.local != 'multistatus' || root.namespaceUri != 'DAV:') {
      throw const WebDavException(WebDavErrorKind.invalidResponse);
    }
    return _children(root, 'response');
  }

  Iterable<XmlElement> _properties(XmlElement response) sync* {
    for (final propstat in _children(response, 'propstat')) {
      final status = _children(propstat, 'status').firstOrNull?.innerText ?? '';
      if (RegExp(r'^HTTP/\S+ 200(?:\s|$)').hasMatch(status)) {
        yield* _children(propstat, 'prop');
      }
    }
  }

  bool _collection(XmlElement prop) => _children(
    prop,
    'resourcetype',
  ).any((type) => _children(type, 'collection').isNotEmpty);
  Future<void> _checkFolder(Uri uri, BackupCancellation? cancellation) async {
    final document = await _propfind(uri, 0, cancellation);
    final exists = _responses(document).any((response) {
      final href = _children(response, 'href').firstOrNull?.innerText;
      if (href == null) return false;
      final target = uri.resolve(href);
      return _sameOrigin(target) &&
          target.path.replaceFirst(RegExp(r'/$'), '') ==
              uri.path.replaceFirst(RegExp(r'/$'), '') &&
          _properties(response).any(_collection);
    });
    if (!exists) throw const WebDavException(WebDavErrorKind.invalidResponse);
  }

  Future<void> ensureDirectory({BackupCancellation? cancellation}) async {
    var segments = config.baseUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    for (final segment in config.remoteDirectory.split('/')) {
      segments = [...segments, segment];
      final uri = config.baseUri.replace(pathSegments: [...segments, '']);
      final status = await _empty(
        'MKCOL',
        uri,
        accepted: {201, 405},
        cancellation: cancellation,
      );
      if (status == 405) await _checkFolder(uri, cancellation);
    }
  }

  Future<void> testConnection({
    required String operationId,
    BackupCancellation? cancellation,
  }) async {
    _checkOperationId(operationId);
    await _checkFolder(config.baseUri, cancellation);
    await ensureDirectory(cancellation: cancellation);
    await _checkFolder(config.folderUri, cancellation);
    final probe = _child('.probe-$operationId');
    var collided = false;
    var written = false;
    try {
      try {
        await _empty(
          'PUT',
          probe,
          headers: {'If-None-Match': '*'},
          body: Stream.value([0]),
          length: 1,
          cancellation: cancellation,
        );
        written = true;
      } on WebDavException catch (error) {
        collided = error.statusCode == 412;
        rethrow;
      }
    } finally {
      if (!collided) {
        if (written) {
          await _empty('DELETE', probe, accepted: {200, 204, 404});
        } else {
          try {
            await _empty('DELETE', probe, accepted: {200, 204, 404});
          } catch (_) {}
        }
      }
    }
  }

  Future<List<RemoteBackup>> listBackups({
    BackupCancellation? cancellation,
  }) async {
    final document = await _propfind(config.folderUri, 1, cancellation);
    final results = <Uri, RemoteBackup>{};
    for (final response in _responses(document)) {
      final href = _children(response, 'href').firstOrNull?.innerText;
      final uri = href == null ? null : _validBackupUri(href);
      if (uri == null) continue;
      for (final prop in _properties(response)) {
        if (_collection(prop)) continue;
        DateTime? modified;
        try {
          modified = HttpDate.parse(
            _children(prop, 'getlastmodified').firstOrNull?.innerText ?? '',
          );
        } catch (_) {}
        final size = int.tryParse(
          _children(prop, 'getcontentlength').firstOrNull?.innerText ?? '',
        );
        results[uri] = RemoteBackup(
          uri: uri,
          name: uri.pathSegments.last,
          size: size == null || size < 0 ? null : size,
          modifiedAt: modified,
        );
      }
    }
    return List.unmodifiable(
      results.values.toList()..sort((a, b) {
        final date = (b.modifiedAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.modifiedAt?.millisecondsSinceEpoch ?? 0,
        );
        return date == 0 ? b.name.compareTo(a.name) : date;
      }),
    );
  }

  void _checkOperationId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid operation ID');
    }
  }

  Future<RemoteBackup> upload(
    File file, {
    required String fileName,
    required String operationId,
    BackupCancellation? cancellation,
    BackupTransferProgress? onProgress,
  }) async {
    _checkOperationId(operationId);
    if (!_isBackupName(fileName)) {
      throw const FormatException('Invalid backup filename');
    }
    await ensureDirectory(cancellation: cancellation);
    final target = _child(fileName);
    final partial = _child('$fileName.$operationId.partial');
    final size = await file.length();
    var moved = false;
    var collided = false;
    try {
      try {
        await _empty(
          'PUT',
          partial,
          headers: {'If-None-Match': '*'},
          body: file.openRead(),
          length: size,
          cancellation: cancellation,
          onUpload: onProgress,
        );
      } on WebDavException catch (error) {
        collided = error.statusCode == 412;
        rethrow;
      }
      await _empty(
        'MOVE',
        partial,
        headers: {'Destination': target.toString(), 'Overwrite': 'F'},
        accepted: {201, 204},
        cancellation: cancellation,
      );
      moved = true;
      return RemoteBackup(
        uri: target,
        name: fileName,
        size: size,
        modifiedAt: DateTime.now().toUtc(),
      );
    } finally {
      if (!moved && !collided) {
        try {
          await _empty('DELETE', partial, accepted: {200, 204, 404});
        } catch (_) {}
      }
    }
  }

  Future<void> download(
    RemoteBackup backup,
    File destination, {
    BackupCancellation? cancellation,
    BackupTransferProgress? onProgress,
  }) async {
    if (_validBackupUri(backup.uri.toString()) == null) {
      throw const WebDavException(WebDavErrorKind.invalidResponse);
    }
    var success = false;
    IOSink? sink;
    try {
      await _request(
        'GET',
        backup.uri,
        accepted: {200},
        cancellation: cancellation,
        receive: (response, body) async {
          sink = destination.openWrite();
          var received = 0;
          await sink!.addStream(
            body.map((chunk) {
              received += chunk.length;
              onProgress?.call(
                received,
                response.contentLength < 0
                    ? backup.size
                    : response.contentLength,
              );
              return chunk;
            }),
          );
          await sink!.flush();
          if (response.contentLength >= 0 &&
              received != response.contentLength) {
            throw const WebDavException(WebDavErrorKind.network);
          }
        },
      );
      await sink?.close();
      sink = null;
      success = true;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (!success && await destination.exists()) await destination.delete();
    }
  }
}
