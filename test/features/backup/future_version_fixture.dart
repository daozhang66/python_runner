import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Reads the first STORED entry in our trusted shared JVM/Flutter ZIP fixture.
/// This deliberately is not a general ZIP reader or production archive parser.
Future<Map<String, dynamic>> futureVersionFixture() async {
  final bytes = await File(
    'android/app/src/test/resources/backup/future-version.zip',
  ).readAsBytes();
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x04034b50 ||
      header.getUint16(8, Endian.little) != 0) {
    throw StateError('Fixture must start with an uncompressed local ZIP entry');
  }
  final nameLength = header.getUint16(26, Endian.little);
  final extraLength = header.getUint16(28, Endian.little);
  final size = header.getUint32(18, Endian.little);
  final name = utf8.decode(bytes.sublist(30, 30 + nameLength));
  if (name != '.python_runner_backup.json') {
    throw StateError('Fixture marker must be first');
  }
  final start = 30 + nameLength + extraLength;
  return jsonDecode(utf8.decode(bytes.sublist(start, start + size)))
      as Map<String, dynamic>;
}
