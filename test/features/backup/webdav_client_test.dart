import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/infrastructure/webdav_client.dart';

class PermissiveOverrides extends HttpOverrides {
  int creations = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    creations++;
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

void main() {
  late HttpServer server;
  late Directory dir;
  late WebDavConfig config;
  late WebDavClient client;
  late Future<void> Function(HttpRequest) handle;
  final calls = <String>[];
  final files = <String, List<int>>{};
  final folders = <String>{};
  final sockets = <Socket>[];
  setUp(() async {
    calls.clear();
    files.clear();
    folders.clear();
    dir = await Directory.systemTemp.createTemp('webdav_');
    final context = SecurityContext()
      ..useCertificateChain('test/features/backup/fixtures/localhost-cert.pem')
      ..usePrivateKey('test/features/backup/fixtures/localhost-key.pem');
    server = await HttpServer.bindSecure('127.0.0.1', 0, context);
    config = WebDavConfig(
      baseUri: Uri.parse('https://localhost:${server.port}/dav/'),
      username: 'me',
      remoteDirectory: '目录/Backups',
    );
    final trust = SecurityContext()
      ..setTrustedCertificates(
        'test/features/backup/fixtures/localhost-cert.pem',
      );
    client = WebDavClient(
      config: config,
      password: 'secret',
      clientFactory: () => HttpClient(context: trust),
    );
    folders.add('/dav/');
    handle = (request) async {
      final path = Uri.decodeComponent(request.uri.path);
      calls.add('${request.method} $path');
      expect(
        request.headers.value('authorization'),
        'Basic ${base64Encode(utf8.encode('me:secret'))}',
      );
      final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      switch (request.method) {
        case 'MKCOL':
          request.response.statusCode = folders.add(path) ? 201 : 405;
        case 'PROPFIND':
          request.response.statusCode = 207;
          request.response.write(
            '<d:multistatus xmlns:d="DAV:"><d:response><d:href>${request.uri}</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>',
          );
        case 'PUT':
          expect(request.contentLength, bytes.length);
          files[path] = bytes;
          request.response.statusCode = 201;
        case 'MOVE':
          expect(request.headers.value('overwrite'), 'F');
          final destination = Uri.decodeComponent(
            Uri.parse(request.headers.value('destination')!).path,
          );
          files[destination] = files.remove(path)!;
          request.response.statusCode = 201;
        case 'DELETE':
          files.remove(path);
          request.response.statusCode = 204;
        case 'GET':
          final bytes = files[path]!;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
      }
      await request.response.close();
    };
    server.listen((r) {
      unawaited(
        handle(r).catchError((Object e) {
          if (e is! SocketException && e is! HttpException) throw e;
        }),
      );
    });
  });
  tearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  test(
    'connection probes read/write and removes only its unique probe',
    () async {
      await client.testConnection(operationId: 'probe');
      expect(calls.first, 'PROPFIND /dav/');
      expect(calls.where((c) => c.startsWith('MKCOL')), [
        'MKCOL /dav/目录/',
        'MKCOL /dav/目录/Backups/',
      ]);
      expect(calls.last, contains('.probe-probe'));
      expect(files, isEmpty);
      await client.testConnection(
        operationId: 'again',
      ); // existing collection 405 verified by PROPFIND
    },
  );
  test(
    'stream upload uses temp PUT then MOVE; download reproduces bytes',
    () async {
      final source = File('${dir.path}/source.zip');
      await source.writeAsBytes(List.generate(200000, (i) => i % 251));
      final progress = <int>[];
      final remote = await client.upload(
        source,
        fileName: 'python-runner-backup-日期 100%.zip',
        operationId: 'upload',
        onProgress: (done, total) => progress.add(done),
      );
      expect(calls[calls.length - 2], endsWith('.upload.partial'));
      expect(calls.last, startsWith('MOVE'));
      expect(files.keys.single, endsWith('日期 100%.zip'));
      final destination = File('${dir.path}/download.zip');
      await client.download(remote, destination);
      expect(await destination.readAsBytes(), await source.readAsBytes());
      expect(progress.last, 200000);
    },
  );
  test('DAV namespace hrefs are decoded once and unrelated or escaping files ignored', () async {
    handle = (r) async {
      r.response.statusCode = 207;
      final folder = config.folderUri.toString();
      String item(
        String href,
        String modified, {
        String type = '',
        String status = '200 OK',
      }) =>
          '<x:response><x:href>$href</x:href><x:propstat><x:prop><x:resourcetype>$type</x:resourcetype><x:getcontentlength>42</x:getcontentlength><x:getlastmodified>$modified</x:getlastmodified></x:prop><x:status>HTTP/1.1 $status</x:status></x:propstat></x:response>';
      r.response.write(
        '<x:multistatus xmlns:x="DAV:">${item('${folder}python-runner-backup-%E4%B8%AD%20100%25.zip', 'Tue, 06 Oct 2026 10:00:00 GMT')}${item('${folder}python-runner-backup-old.zip', 'Mon, 05 Oct 2026 10:00:00 GMT')}${item('https://escape.example/python-runner-backup-bad.zip', '')}${item('${folder}python-runner-backup-incomplete.zip.partial', '')}${item('${folder}unrelated.zip', '')}${item('${folder}python-runner-backup-dir.zip', '', type: '<x:collection/>')}${item('${folder}python-runner-backup-no.zip', '', status: '404 Not Found')}${item('$folder../python-runner-backup-escape.zip', '')}</x:multistatus>',
      );
      await r.response.close();
    };
    final backups = await client.listBackups();
    expect(backups.map((b) => b.name), [
      'python-runner-backup-中 100%.zip',
      'python-runner-backup-old.zip',
    ]);
    expect(backups.first.size, 42);
  });
  test('auth and redirect errors are typed and never include raw HTML or credentials', () async {
    for (final status in [401, 403, 302, 405]) {
      handle = (r) async {
        r.response.statusCode = status;
        r.response.headers.set('location', 'https://escape.example');
        r.response.write('<html>secret</html>');
        await r.response.close();
      };
      await expectLater(
        client.listBackups(),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('secret')),
          ),
        ),
      );
    }
  });
  test('MKCOL 409 is a conflict; existing 405 must actually be a collection', () async {
    for (final status in [409, 405]) {
      handle = (r) async {
        r.response.statusCode = r.method == 'MKCOL' ? status : 207;
        if (r.method == 'PROPFIND') {
          r.response.write(
            '<d:multistatus xmlns:d="DAV:"><d:response><d:href>${r.uri}</d:href><d:propstat><d:prop><d:resourcetype/></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>',
          );
        }
        await r.response.close();
      };
      await expectLater(
        client.ensureDirectory(),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.kind,
            'kind',
            status == 409
                ? WebDavErrorKind.conflict
                : WebDavErrorKind.invalidResponse,
          ),
        ),
      );
    }
  });
  test(
    'MOVE failure cleans only own partial upload and preserves history',
    () async {
      final original = handle;
      handle = (r) async {
        if (r.method == 'MOVE') {
          r.response.statusCode = 403;
          await r.response.close();
        } else {
          await original(r);
        }
      };
      files['/old-user-backup.zip'] = [1, 2, 3];
      final source = File('${dir.path}/source.zip');
      await source.writeAsBytes([7, 8, 9]);
      await expectLater(
        client.upload(
          source,
          fileName: 'python-runner-backup-test.zip',
          operationId: 'failed',
        ),
        throwsA(isA<WebDavException>()),
      );
      expect(files, {
        '/old-user-backup.zip': [1, 2, 3],
      });
      expect(calls.last, endsWith('.failed.partial'));
    },
  );
  test(
    'upload precondition collision never deletes a pre-existing partial',
    () async {
      final original = handle;
      handle = (r) async {
        if (r.method == 'PUT') {
          calls.add('PUT');
          r.response.statusCode = 412;
          await r.response.close();
        } else {
          await original(r);
        }
      };
      final source = File('${dir.path}/source.zip');
      await source.writeAsBytes([7]);
      await expectLater(
        client.upload(
          source,
          fileName: 'python-runner-backup-test.zip',
          operationId: 'collision',
        ),
        throwsA(isA<WebDavException>()),
      );
      expect(calls.where((c) => c.startsWith('DELETE')), isEmpty);
    },
  );
  test(
    'oversized XML is bounded and cross-origin downloads never make a request',
    () async {
      handle = (r) async {
        r.response.statusCode = 207;
        r.response.add(List.filled(WebDavClient.maxXmlBytes + 1, 32));
        try {
          await r.response.close();
        } on SocketException {
          // The bounded reader closes the connection before this body finishes.
        }
      };
      await expectLater(
        client.listBackups(),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.kind,
            'kind',
            WebDavErrorKind.invalidResponse,
          ),
        ),
      );
      await expectLater(
        client.download(
          RemoteBackup(
            uri: Uri.parse(
              'https://other.example/python-runner-backup-test.zip',
            ),
            name: 'python-runner-backup-test.zip',
            size: 1,
          ),
          File('${dir.path}/bad.zip'),
        ),
        throwsA(isA<WebDavException>()),
      );
      expect(await File('${dir.path}/bad.zip').exists(), false);
    },
  );
  test('cancel mid-download deletes partial local file', () async {
    final cancellation = BackupCancellation();
    handle = (r) async {
      final socket = await r.response.detachSocket(writeHeaders: false);
      sockets.add(socket);
      socket.add(
        ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 999999\r\n\r\n'),
      );
      socket.add(List.filled(65536, 1));
      await socket.flush();
    };
    final destination = File('${dir.path}/partial.zip');
    final backup = RemoteBackup(
      uri: config.folderUri.resolve('python-runner-backup-test.zip'),
      name: 'python-runner-backup-test.zip',
      size: 999999,
    );
    await expectLater(
      client.download(
        backup,
        destination,
        cancellation: cancellation,
        onProgress: (_, _) => cancellation.cancel(),
      ),
      throwsA(isA<BackupCancelledException>()),
    );
    expect(await destination.exists(), isFalse);
  });
  test('cancel upload removes its partial and never publishes MOVE', () async {
    final source = File('${dir.path}/source.zip');
    await source.writeAsBytes(List.filled(256 * 1024, 7));
    final cancellation = BackupCancellation();
    await expectLater(
      client.upload(
        source,
        fileName: 'python-runner-backup-cancel.zip',
        operationId: 'cancel',
        cancellation: cancellation,
        onProgress: (_, _) => cancellation.cancel(),
      ),
      throwsA(isA<BackupCancelledException>()),
    );
    expect(calls.where((c) => c.startsWith('MOVE')), isEmpty);
    expect(
      calls.last,
      'DELETE /dav/目录/Backups/python-runner-backup-cancel.zip.cancel.partial',
    );
    expect(files, isEmpty);
  });
  test('midstream disconnect deletes local partial', () async {
    handle = (r) async {
      final socket = await r.response.detachSocket(writeHeaders: false);
      sockets.add(socket);
      socket.add(
        ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 999999\r\n\r\n'),
      );
      socket.add(List.filled(65536, 1));
      await socket.flush();
      await socket.close();
    };
    final destination = File('${dir.path}/partial.zip');
    await expectLater(
      client.download(
        RemoteBackup(
          uri: config.folderUri.resolve('python-runner-backup-test.zip'),
          name: 'python-runner-backup-test.zip',
          size: 999999,
        ),
        destination,
      ),
      throwsA(isA<WebDavException>()),
    );
    expect(await destination.exists(), isFalse);
  });
  test(
    'production client ignores globally permissive certificate overrides',
    () async {
      final override = PermissiveOverrides();
      final old = HttpOverrides.current;
      HttpOverrides.global = override;
      try {
        final production = WebDavClient(config: config, password: 'secret');
        await expectLater(
          production.listBackups(),
          throwsA(isA<WebDavException>()),
        );
        expect(override.creations, 0);
      } finally {
        HttpOverrides.global = old;
      }
    },
  );
}
