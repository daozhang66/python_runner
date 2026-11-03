import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/ssh/application/ssh_command_builder.dart';
import 'package:python_runner/features/ssh/application/ssh_keys.dart';

void main() {
  test('shQuote escapes single quotes', () {
    expect(shQuote("it's"), r"'it'\''s'");
    expect(shQuote('plain'), "'plain'");
  });

  test('shQuotePath keeps ~ working through \$HOME', () {
    expect(shQuotePath('~'), r'"$HOME"');
    expect(shQuotePath('~/python_runner'), '"\$HOME"/\'python_runner\'');
    expect(shQuotePath('/opt/my app'), "'/opt/my app'");
  });

  test('safeRemoteFileName drops directories and control characters', () {
    expect(safeRemoteFileName('../x/y.py'), 'y.py');
    expect(safeRemoteFileName(r'a\b.py'), 'b.py');
    expect(safeRemoteFileName(''), 'script.py');
    expect(safeRemoteFileName('a\nb.py'), 'a_b.py');
  });

  test('upload and run commands are quoted', () {
    expect(
      buildUploadCommand(remoteDir: '~/python_runner', fileName: 'a b.py'),
      '''mkdir -p "\$HOME"/'python_runner' && cat > "\$HOME"/'python_runner'/'a b.py\'''',
    );
    final run = buildRunCommand(
      remoteDir: '~/python_runner',
      fileName: 'a b.py',
      pythonCommand: 'python3 -u',
    );
    expect(
      run,
      startsWith('''cd "\$HOME"/'python_runner' && PYTHONUNBUFFERED=1 python3 -u 'a b.py'; '''),
    );
    expect(run, contains('[exit code %s]'));
  });

  test('blank python command falls back to python3', () {
    final run = buildRunCommand(
      remoteDir: '/tmp',
      fileName: 'x.py',
      pythonCommand: '  ',
    );
    expect(run, contains('PYTHONUNBUFFERED=1 python3 '));
  });

  test('generated ed25519 key round-trips to the same public key', () {
    final key = generateEd25519Key(comment: 'test');
    expect(key.privatePem, contains('BEGIN OPENSSH PRIVATE KEY'));
    expect(
      key.publicLine,
      startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA'),
    );
    final derived = publicKeyLineFromPem(key.privatePem, comment: 'test');
    expect(derived, key.publicLine);
  });
}
