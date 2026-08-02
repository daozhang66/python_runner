import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/network_debug_config.dart';
import '../services/request_override_config.dart';

class RequestOverrideEditorPage extends StatefulWidget {
  const RequestOverrideEditorPage({super.key});

  @override
  State<RequestOverrideEditorPage> createState() =>
      _RequestOverrideEditorPageState();
}

class _RequestOverrideEditorPageState extends State<RequestOverrideEditorPage> {
  final _userAgentController = TextEditingController();
  final _headersController = TextEditingController();
  final _cookieController = TextEditingController();
  final _timeoutController = TextEditingController();
  final _previewHostController = TextEditingController();
  late List<Map<String, dynamic>> _rules;
  bool _followRedirects = true;
  bool _useDebugProxyWhenUnset = false;
  bool _saving = false;

  RequestOverrideConfig get _config => RequestOverrideConfig.instance;

  @override
  void initState() {
    super.initState();
    _loadFromConfig();
  }

  void _loadFromConfig() {
    _userAgentController.text = _config.globalUserAgent;
    _headersController.text = _config.globalHeaders;
    _cookieController.text = _config.globalCookie;
    _timeoutController.text = _config.defaultTimeout.toString();
    _followRedirects = _config.followRedirects;
    _useDebugProxyWhenUnset = _config.forceProxy;
    _rules = _config.domainRules;
  }

  @override
  void dispose() {
    _userAgentController.dispose();
    _headersController.dispose();
    _cookieController.dispose();
    _timeoutController.dispose();
    _previewHostController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final timeout = int.tryParse(_timeoutController.text.trim());
    if (timeout == null || timeout < 0) {
      _showError(l10n.invalidOverrideConfig);
      return;
    }
    setState(() => _saving = true);
    try {
      await _config.applyOverrides(
        userAgent: _userAgentController.text,
        headersJson: _headersController.text,
        cookie: _cookieController.text,
        timeoutSeconds: timeout,
        followRedirects: _followRedirects,
        useDebugProxyWhenUnset:
            NetworkDebugConfig.instance.hasProxy && _useDebugProxyWhenUnset,
        domainRules: _rules,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.overridesSaved)));
    } on FormatException catch (error) {
      if (mounted) {
        _showError('${l10n.invalidOverrideConfig}: ${error.message}');
      }
    } catch (error) {
      if (mounted) _showError('${l10n.invalidOverrideConfig}: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyConfiguration() async {
    await Clipboard.setData(ClipboardData(text: _config.exportOverrides()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.overrideConfigCopied)),
    );
  }

  Future<void> _importConfiguration() async {
    final l10n = AppLocalizations.of(context)!;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final controller = TextEditingController(text: data?.text ?? '');
    final shouldImport = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.importOverrideConfig),
        content: TextField(
          controller: controller,
          minLines: 8,
          maxLines: 14,
          decoration: InputDecoration(hintText: l10n.pasteOverrideConfigHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.importOverrideConfig),
          ),
        ],
      ),
    );
    if (shouldImport != true) {
      controller.dispose();
      return;
    }
    try {
      await _config.importOverrides(controller.text);
      if (!mounted) return;
      setState(_loadFromConfig);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.overrideConfigImported)));
    } on FormatException catch (error) {
      if (mounted) {
        _showError('${l10n.invalidOverrideConfig}: ${error.message}');
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editRule([int? index]) async {
    final l10n = AppLocalizations.of(context)!;
    final existing = index == null ? null : _rules[index];
    final domain =
        TextEditingController(text: existing?['domain'] as String? ?? '');
    final userAgent =
        TextEditingController(text: existing?['user_agent'] as String? ?? '');
    final cookie =
        TextEditingController(text: existing?['cookie'] as String? ?? '');
    final headers = TextEditingController(
      text: existing?['headers'] is Map ? jsonEncode(existing!['headers']) : '',
    );
    String? domainError;
    String? headersError;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title:
                Text(index == null ? l10n.addDomainRule : l10n.editDomainRule),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: domain,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setDialogState(() => domainError = null),
                    decoration: InputDecoration(
                      labelText: l10n.domainPattern,
                      errorText: domainError == null
                          ? null
                          : l10n.invalidOverrideConfig,
                    ),
                  ),
                  TextField(
                    controller: userAgent,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration:
                        InputDecoration(labelText: l10n.globalUserAgent),
                  ),
                  TextField(
                    controller: cookie,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(labelText: l10n.globalCookie),
                  ),
                  TextField(
                    controller: headers,
                    minLines: 3,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setDialogState(() => headersError = null),
                    decoration: InputDecoration(
                      labelText: l10n.ruleHeaders,
                      errorText: headersError == null
                          ? null
                          : l10n.invalidOverrideConfig,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final nextDomainError =
                      RequestOverrideConfig.validateDomainPattern(domain.text);
                  final nextHeadersError =
                      RequestOverrideConfig.validateHeadersJson(headers.text);
                  if (nextDomainError != null || nextHeadersError != null) {
                    setDialogState(() {
                      domainError = nextDomainError;
                      headersError = nextHeadersError;
                    });
                    return;
                  }
                  final rule = <String, dynamic>{'domain': domain.text.trim()};
                  if (userAgent.text.trim().isNotEmpty) {
                    rule['user_agent'] = userAgent.text.trim();
                  }
                  if (cookie.text.trim().isNotEmpty) {
                    rule['cookie'] = cookie.text.trim();
                  }
                  if (headers.text.trim().isNotEmpty) {
                    rule['headers'] = jsonDecode(headers.text) as Map;
                  }
                  Navigator.pop(context, rule);
                },
                child: Text(l10n.save),
              ),
            ],
          );
        },
      ),
    );
    domain.dispose();
    userAgent.dispose();
    cookie.dispose();
    headers.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _rules.add(result);
      } else {
        _rules[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final hasProxy = NetworkDebugConfig.instance.hasProxy;
    final headersError =
        RequestOverrideConfig.validateHeadersJson(_headersController.text);
    final preview = RequestOverrideConfig.previewForValues(
      host: _previewHostController.text,
      userAgent: _userAgentController.text,
      headersJson: _headersController.text,
      cookie: _cookieController.text,
      domainRules: _rules,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.requestOverrideSettings),
        actions: [
          IconButton(
            tooltip: l10n.copyOverrideConfig,
            onPressed: _copyConfiguration,
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: l10n.pasteImportOverrides,
            onPressed: _importConfiguration,
            icon: const Icon(Icons.content_paste_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EditorSection(
            title: l10n.globalOverrides,
            children: [
              TextField(
                controller: _userAgentController,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.globalUserAgent),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cookieController,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.globalCookie),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _headersController,
                minLines: 3,
                maxLines: 7,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n.globalHeaders),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _timeoutController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: l10n.defaultRequestTimeout,
                  helperText: l10n.noDefaultTimeout,
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.followRedirects),
                value: _followRedirects,
                onChanged: (value) => setState(() => _followRedirects = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.useDebugProxyWhenUnset),
                subtitle: hasProxy ? null : Text(l10n.noValidDebugProxy),
                value: hasProxy && _useDebugProxyWhenUnset,
                onChanged: hasProxy
                    ? (value) => setState(() => _useDebugProxyWhenUnset = value)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EditorSection(
            title: l10n.domainRules,
            children: [
              Text(l10n.domainRulesHint,
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              if (_rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(l10n.noDomainRules,
                      style: TextStyle(color: colors.onSurfaceVariant)),
                ),
              for (var index = 0; index < _rules.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_rules[index]['domain'] as String),
                  subtitle: Text(
                    [
                      if ((_rules[index]['user_agent'] as String?)
                              ?.isNotEmpty ??
                          false)
                        l10n.globalUserAgent,
                      if ((_rules[index]['cookie'] as String?)?.isNotEmpty ??
                          false)
                        l10n.globalCookie,
                      if (_rules[index]['headers'] is Map) l10n.globalHeaders,
                    ].join(' · '),
                  ),
                  leading: Text('${index + 1}',
                      style: TextStyle(color: colors.primary)),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Up',
                        onPressed: index == 0
                            ? null
                            : () => setState(() {
                                  final rule = _rules.removeAt(index);
                                  _rules.insert(index - 1, rule);
                                }),
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: 'Down',
                        onPressed: index == _rules.length - 1
                            ? null
                            : () => setState(() {
                                  final rule = _rules.removeAt(index);
                                  _rules.insert(index + 1, rule);
                                }),
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      IconButton(
                        tooltip: l10n.edit,
                        onPressed: () => _editRule(index),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: l10n.delete,
                        onPressed: () => setState(() => _rules.removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _editRule,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addDomainRule),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EditorSection(
            title: l10n.previewEffectiveOverrides,
            children: [
              TextField(
                controller: _previewHostController,
                onChanged: (_) => setState(() {}),
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l10n.testDomain),
              ),
              const SizedBox(height: 10),
              Text(
                preview.matchedRuleIndex == null
                    ? l10n.noMatchingRule
                    : l10n.matchedRule(preview.matchedRuleIndex! + 1),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (preview.userAgent.isNotEmpty)
                Text('User-Agent: ${preview.userAgent}'),
              if (preview.cookie.isNotEmpty) Text('Cookie: ${preview.cookie}'),
              if (preview.headers.isNotEmpty)
                Text(jsonEncode(preview.headers),
                    style: const TextStyle(fontFamily: 'monospace')),
              if (headersError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.invalidOverrideConfig,
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.saveOverrides),
          ),
        ],
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}
