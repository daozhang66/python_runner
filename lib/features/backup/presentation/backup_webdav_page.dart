import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../application/backup_providers.dart';
import '../infrastructure/webdav_client.dart';
import 'backup_widgets.dart';

class BackupWebDavPage extends ConsumerStatefulWidget {
  const BackupWebDavPage({super.key});
  @override
  ConsumerState<BackupWebDavPage> createState() => _BackupWebDavPageState();
}

class _BackupWebDavPageState extends ConsumerState<BackupWebDavPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _directory;
  final _password = TextEditingController();
  bool _obscure = true;
  late final bool _hasPassword;
  bool _lastWasSave = false;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    final profile = ref.read(backupControllerProvider).state.profile;
    _url = TextEditingController(text: profile?.baseUri.toString());
    _username = TextEditingController(text: profile?.username);
    _directory = TextEditingController(
      text: profile?.remoteDirectory ?? 'PythonRunner/Backups',
    );
    _hasPassword = profile != null;
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _directory.dispose();
    _password.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool save}) async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _lastWasSave = save;
    final profile = WebDavConfig(
      baseUri: Uri.parse(_url.text.trim()),
      username: _username.text.trim(),
      remoteDirectory: _directory.text.trim(),
    );
    final password = _hasPassword && _password.text.isEmpty
        ? null
        : _password.text;
    final c = ref.read(backupControllerProvider);
    if (save) {
      await c.saveWebDavProfile(profile, password: password);
      if (mounted && c.state.error == null) Navigator.pop(context, true);
    } else {
      await c.testWebDavConnection(profile: profile, password: password);
    }
    if (mounted && _scroll.hasClients && (c.state.error != null || !save)) {
      _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(backupControllerProvider).state;
    final l = AppLocalizations.of(context)!;
    InputDecoration decoration(
      String label, {
      String? hint,
      String? helper,
      Widget? suffix,
    }) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 6,
      errorMaxLines: 6,
      suffixIcon: suffix,
    );
    return BackupPageFrame(
      title: l.backupWebDavTitle,
      scrollController: _scroll,
      canPop: !s.busy,
      children: [
        BackupStatusPanel(onRetry: () => _submit(save: _lastWasSave)),
        Form(
          key: _form,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('webdav-url'),
                  controller: _url,
                  enabled: !s.busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: decoration(
                    l.backupServerUrl,
                    hint: l.backupServerHint,
                  ),
                  validator: (v) {
                    try {
                      WebDavConfig(baseUri: Uri.parse(v!.trim()), username: '');
                      return null;
                    } catch (_) {
                      return l.backupInvalidUrl;
                    }
                  },
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('webdav-username'),
                  controller: _username,
                  enabled: !s.busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: decoration(l.backupUsername),
                  validator: (v) =>
                      v == null ||
                          v.trim().isEmpty ||
                          v.contains(':') ||
                          RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)
                      ? l.backupInvalidUsername
                      : null,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('webdav-password'),
                  controller: _password,
                  enabled: !s.busy,
                  obscureText: _obscure,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: decoration(
                    l.backupPassword,
                    helper: _hasPassword
                        ? l.backupKeepPassword
                        : l.backupPasswordPrivate,
                    suffix: IconButton(
                      tooltip: _obscure
                          ? l.backupShowPassword
                          : l.backupHidePassword,
                      onPressed: s.busy
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (v) => !_hasPassword && (v == null || v.isEmpty)
                      ? l.backupPasswordRequired
                      : null,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const ValueKey('webdav-directory'),
                  controller: _directory,
                  enabled: !s.busy,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: decoration(l.backupRemoteDirectory),
                  validator: (v) {
                    try {
                      WebDavConfig(
                        baseUri: Uri.parse('https://validation.invalid'),
                        username: '',
                        remoteDirectory: v!.trim(),
                      );
                      return null;
                    } catch (_) {
                      return l.backupInvalidDirectory;
                    }
                  },
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: s.busy ? null : () => Navigator.pop(context),
                      child: Text(l.cancel),
                    ),
                    TextButton(
                      key: const ValueKey('webdav-test'),
                      onPressed: s.busy ? null : () => _submit(save: false),
                      child: Text(l.backupTestConnection),
                    ),
                    OutlinedButton(
                      key: const ValueKey('webdav-save'),
                      onPressed: s.busy ? null : () => _submit(save: true),
                      child: Text(l.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
