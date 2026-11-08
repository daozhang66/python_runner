import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/ssh_keys.dart';
import '../../application/ssh_profile_store.dart';
import '../../domain/ssh_profile.dart';
import '../ssh_dialogs.dart';
import '../ssh_text.dart';

class SshProfileEditPage extends StatefulWidget {
  const SshProfileEditPage({super.key, this.profile});

  /// The host being edited, or null to add a new one.
  final SshProfile? profile;

  @override
  State<SshProfileEditPage> createState() => _SshProfileEditPageState();
}

class _SshProfileEditPageState extends State<SshProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  final _remoteDir = TextEditingController(text: SshProfile.defaultRemoteDir);
  final _python = TextEditingController(text: SshProfile.defaultPythonCommand);

  SshAuthType _auth = SshAuthType.password;
  SshSecrets _saved = SshSecrets.empty;
  bool _clearSaved = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    if (profile != null) {
      _name.text = profile.name;
      _host.text = profile.host;
      _port.text = profile.port.toString();
      _user.text = profile.username;
      _auth = profile.authType;
      _remoteDir.text = profile.remoteDir;
      _python.text = profile.pythonCommand;
      _loadSecrets(profile.id);
    } else {
      _loading = false;
    }
  }

  Future<void> _loadSecrets(String id) async {
    final secrets = await SshProfileStore.instance.loadSecrets(id);
    if (!mounted) return;
    setState(() {
      _saved = secrets;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    _remoteDir.dispose();
    _python.dispose();
    super.dispose();
  }

  SshSecrets get _base => _clearSaved ? SshSecrets.empty : _saved;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = SshText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final host = _host.text.trim();
    final user = _user.text.trim();
    final profile = SshProfile(
      id: widget.profile?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? '$user@$host' : _name.text.trim(),
      host: host,
      port: int.parse(_port.text.trim()),
      username: user,
      authType: _auth,
      remoteDir: _remoteDir.text.trim().isEmpty
          ? SshProfile.defaultRemoteDir
          : _remoteDir.text.trim(),
      pythonCommand: _python.text.trim().isEmpty
          ? SshProfile.defaultPythonCommand
          : _python.text.trim(),
    );
    final store = SshProfileStore.instance;
    await store.upsertProfile(profile);

    final typedKey = _privateKey.text.trim();
    final base = _base;
    final secrets = SshSecrets(
      password: _password.text.isNotEmpty ? _password.text : base.password,
      privateKey: typedKey.isNotEmpty ? '$typedKey\n' : base.privateKey,
      passphrase:
          _passphrase.text.isNotEmpty ? _passphrase.text : base.passphrase,
    );
    final stored = await store.saveSecrets(profile.id, secrets);
    if (!stored && !secrets.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法写入系统安全存储，凭据没有保存，连接时会再询问',
              'Could not write to secure storage; credentials were not saved and will be asked for on connect',
            ),
          ),
        ),
      );
    }
    navigator.pop(profile);
  }

  Future<void> _pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _privateKey.text = text.trim();
      _auth = SshAuthType.privateKey;
    });
  }

  Future<void> _generateKey() async {
    final host = _host.text.trim();
    final key = generateEd25519Key(
      comment: host.isEmpty ? 'python-runner' : 'python-runner@$host',
    );
    setState(() {
      _privateKey.text = key.privatePem.trim();
      _auth = SshAuthType.privateKey;
    });
    await showSshPublicKeyDialog(context, key.publicLine);
  }

  Future<void> _showPublicKey() async {
    final t = SshText.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final typed = _privateKey.text.trim();
    final pem = typed.isNotEmpty ? typed : (_base.privateKey ?? '');
    final passphrase =
        _passphrase.text.isNotEmpty ? _passphrase.text : _base.passphrase;
    final line = pem.isEmpty
        ? null
        : publicKeyLineFromPem(pem, passphrase: passphrase);
    if (line == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法读取私钥（格式不对，或需要先填写口令）',
              'Cannot read the private key (bad format, or a passphrase is needed)',
            ),
          ),
        ),
      );
      return;
    }
    await showSshPublicKeyDialog(context, line);
  }

  String? _required(String? value, SshText t) =>
      (value == null || value.trim().isEmpty) ? t('必填', 'Required') : null;

  @override
  Widget build(BuildContext context) {
    final t = SshText.of(context);
    final hasSavedKey = (_base.privateKey ?? '').isNotEmpty;
    final hasSavedPassword = (_base.password ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile == null
              ? t('添加主机', 'Add host')
              : t('编辑主机', 'Edit host'),
        ),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: Text(t('保存', 'Save')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: t('名称（可选）', 'Name (optional)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _host,
                          autocorrect: false,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: t('主机地址', 'Host'),
                            hintText: '192.168.1.10',
                          ),
                          validator: (value) => _required(value, t),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: t('端口', 'Port')),
                          validator: (value) {
                            final port = int.tryParse((value ?? '').trim());
                            if (port == null || port < 1 || port > 65535) {
                              return t('1-65535', '1-65535');
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _user,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: t('用户名', 'Username')),
                    validator: (value) => _required(value, t),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<SshAuthType>(
                    segments: [
                      ButtonSegment(
                        value: SshAuthType.password,
                        label: Text(t('密码', 'Password')),
                        icon: const Icon(Icons.password),
                      ),
                      ButtonSegment(
                        value: SshAuthType.privateKey,
                        label: Text(t('私钥', 'Private key')),
                        icon: const Icon(Icons.vpn_key_outlined),
                      ),
                    ],
                    selected: {_auth},
                    onSelectionChanged: (selection) =>
                        setState(() => _auth = selection.first),
                  ),
                  const SizedBox(height: 12),
                  if (_auth == SshAuthType.password)
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: t('密码', 'Password'),
                        helperText: hasSavedPassword
                            ? t('已保存，留空则保持不变', 'Saved — leave empty to keep')
                            : t('留空则每次连接时询问', 'Leave empty to be asked on each connect'),
                      ),
                    )
                  else ...[
                    TextFormField(
                      controller: _privateKey,
                      minLines: 3,
                      maxLines: 6,
                      autocorrect: false,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(
                        labelText: t('私钥（OpenSSH / PEM）', 'Private key (OpenSSH / PEM)'),
                        alignLabelWithHint: true,
                        helperText: hasSavedKey
                            ? t('已保存，留空则保持不变', 'Saved — leave empty to keep')
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pasteKey,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: Text(t('从剪贴板粘贴', 'Paste')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _generateKey,
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: Text(t('生成密钥', 'Generate')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showPublicKey,
                          icon: const Icon(Icons.key, size: 18),
                          label: Text(t('查看公钥', 'Public key')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passphrase,
                      obscureText: true,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: t('私钥口令（可选）', 'Key passphrase (optional)'),
                        helperText: t(
                          '加密的私钥留空则每次连接时询问',
                          'For an encrypted key, leave empty to be asked on each connect',
                        ),
                      ),
                    ),
                  ],
                  if (!_saved.isEmpty && widget.profile != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearSaved
                            ? null
                            : () => setState(() {
                                  _clearSaved = true;
                                  _password.clear();
                                  _privateKey.clear();
                                  _passphrase.clear();
                                }),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(
                          _clearSaved
                              ? t('保存时将清除已存凭据', 'Saved credentials will be cleared')
                              : t('清除已保存的凭据', 'Clear saved credentials'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _remoteDir,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t('远程脚本目录', 'Remote script directory'),
                      helperText: t(
                        '远程运行时脚本会上传到这里，~ 表示用户主目录',
                        'Scripts are uploaded here for remote runs; ~ is the home directory',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _python,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t('远程 Python 命令', 'Remote Python command'),
                      helperText: t(
                        '例如 python3，或 ~/venv/bin/python',
                        'For example python3 or ~/venv/bin/python',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
