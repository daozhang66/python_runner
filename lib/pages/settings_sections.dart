// ignore_for_file: invalid_use_of_protected_member

part of 'settings_page.dart';

extension _SettingsSections on _SettingsPageState {
  Widget _buildRuntimeSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _SectionCard(
          icon: Icons.memory,
          title: l10n.runtimeEngine,
          children: [
            ListTile(
              leading: const Icon(Icons.memory),
              title: Text(l10n.runtimeEngine),
              subtitle: Text(
                _runtimeBackend == RuntimeManager.chaquopyBackendId
                    ? l10n.chaquopyDefault
                    : l10n.linuxLikeExperimental,
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showRuntimeBackendPicker,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _runtimeBackendSubtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _buildRuntimeInstallPanel(l10n),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.pypiSource,
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text(
                        l10n.useOfficialSourceWhenEmpty,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _mirrorController,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            hintText: 'https://pypi.org/simple',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _saveMirror,
                        icon: const Icon(Icons.save),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _restoreOfficialMirror,
                      child: Text(l10n.restoreOfficialSource),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _SectionCard(
          icon: Icons.code,
          title: l10n.script,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(l10n.executionTimeout,
                          style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text(
                        _timeout == 0
                            ? l10n.unlimited
                            : _timeout >= 3600
                                ? l10n
                                    .hours((_timeout / 3600).toStringAsFixed(1))
                                : _timeout >= 60
                                    ? l10n.minutes(
                                        (_timeout / 60).toStringAsFixed(0))
                                    : l10n.seconds(_timeout),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _timeout == 0
                        ? 0
                        : _timeout <= 60
                            ? _timeout.toDouble()
                            : _timeout <= 600
                                ? 60 + (_timeout - 60) * 40 / 540
                                : _timeout <= 3600
                                    ? 100 + (_timeout - 600) * 40 / 3000
                                    : 140 + (_timeout - 3600) * 10 / 32400,
                    min: 0,
                    max: 150,
                    divisions: 150,
                    label: _timeout == 0
                        ? l10n.unlimited
                        : _timeout >= 3600
                            ? '${(_timeout / 3600).toStringAsFixed(1)}h'
                            : _timeout >= 60
                                ? '${(_timeout / 60).toStringAsFixed(0)}m'
                                : '${_timeout}s',
                    onChanged: (v) {
                      int val;
                      if (v == 0) {
                        val = 0;
                      } else if (v <= 60) {
                        val = v.round();
                      } else if (v <= 100) {
                        val = 60 + ((v - 60) * 540 / 40).round();
                        val = (val / 60).round() * 60;
                      } else if (v <= 140) {
                        val = 600 + ((v - 100) * 3000 / 40).round();
                        val = (val / 300).round() * 300;
                      } else {
                        val = 3600 + ((v - 140) * 32400 / 10).round();
                        val = (val / 1800).round() * 1800;
                      }
                      setState(() => _timeout = val);
                    },
                    onChangeEnd: (v) => _saveTimeout(_timeout),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(l10n.workingDirectory),
              subtitle: Text(
                _workingDir ?? l10n.defaultWorkingDirectory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _pickWorkingDir,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.scriptWorkingDirectoryDescription,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: Text(l10n.scriptExportDirectory),
              subtitle: Text(
                _exportDir ?? l10n.defaultDownloadDirectory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _pickExportDir,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNetworkDebugSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _SectionCard(
          icon: Icons.http,
          title: l10n.network,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.developer_mode),
              title: Text(l10n.networkDebugMode),
              subtitle: Text(l10n.networkDebugModeDescription,
                  style: const TextStyle(fontSize: 12)),
              value: _netDebugMode,
              onChanged: _toggleNetDebugMode,
            ),
            if (_netDebugMode) ...[
              SwitchListTile(
                secondary: Icon(
                  Icons.lock_open,
                  color: _netAllowInsecure
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text(l10n.allowInsecureCertificates),
                subtitle: Text(
                  _netAllowInsecure
                      ? l10n.insecureCertificatesOn
                      : l10n.insecureCertificatesOff,
                  style: TextStyle(
                    fontSize: 12,
                    color: _netAllowInsecure
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                value: _netAllowInsecure,
                onChanged: _toggleAllowInsecure,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.proxyConfigurationOptional,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(l10n.proxyConfigurationDescription,
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _proxyHostController,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: InputDecoration(
                              hintText: '192.168.1.100',
                              labelText: l10n.proxyAddress,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _proxyPortController,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              hintText: '8888',
                              labelText: l10n.port,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _saveProxyConfig,
                          icon: const Icon(Icons.save),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_outlined),
              title: Text(l10n.recordNetworkRequests),
              subtitle: Text(l10n.recordNetworkRequestsDescription,
                  style: TextStyle(fontSize: 12)),
              value: _recordRequests,
              onChanged: (v) async {
                await RequestOverrideConfig.instance.setRecordRequests(v);
                setState(() => _recordRequests = v);
              },
            ),
            if (_recordRequests)
              SwitchListTile(
                secondary: const Icon(Icons.description_outlined),
                title: Text(l10n.recordResponsePreview),
                subtitle: Text(l10n.responsePreviewLimit,
                    style: TextStyle(fontSize: 12)),
                value: _recordResponseBody,
                onChanged: (v) async {
                  await RequestOverrideConfig.instance.setRecordResponseBody(v);
                  setState(() => _recordResponseBody = v);
                },
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: Icon(
                Icons.tune,
                color: _overrideEnabled
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(l10n.enableRequestOverrides),
              subtitle: Text(
                _overrideEnabled
                    ? l10n.requestOverridesOn
                    : l10n.requestOverridesOff,
                style: TextStyle(
                  fontSize: 12,
                  color: _overrideEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              value: _overrideEnabled,
              onChanged: (v) async {
                if (v && mounted) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      backgroundColor:
                          Theme.of(ctx).colorScheme.surfaceContainerHigh,
                      surfaceTintColor: Colors.transparent,
                      title: Text(l10n.enableRequestOverrides),
                      content: Text(l10n.requestOverrideWarning),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.confirmEnable),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
                await RequestOverrideConfig.instance.setOverrideEnabled(v);
                setState(() => _overrideEnabled = v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: Text(l10n.requestOverrideSettings),
              subtitle: Text(
                _overrideEnabled
                    ? l10n.requestOverridesOn
                    : l10n.requestOverridesOff,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const RequestOverrideEditorPage(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiagnosticsSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _SectionCard(
          icon: Icons.build_outlined,
          title: l10n.systemTools,
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(l10n.appLogs),
              subtitle:
                  Text(l10n.appLogsDescription, style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppLogsPage(),
                ),
              ),
              onLongPress: _viewSystemLogs,
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(l10n.exportFullLogs),
              subtitle: Text(l10n.exportFullLogsDescription,
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportSystemLogs,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _SectionCard(
          icon: Icons.info_outline,
          title: l10n.aboutApp,
          children: [
            ListTile(
              leading: _checkingUpdate
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt),
              title: Text(l10n.checkForUpdates),
              subtitle: Text(l10n.checkForUpdatesDescription,
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checkingUpdate ? null : _checkForUpdates,
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(l10n.updateLog),
              subtitle: Text(l10n.updateLogDescription,
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openUpdateLogPage,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.update_outlined),
              title: Text(l10n.autoCheckUpdates),
              subtitle: Text(l10n.autoCheckUpdatesDescription,
                  style: const TextStyle(fontSize: 12)),
              value: _autoCheckUpdates,
              onChanged: _setAutoCheckUpdates,
            ),
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: Text(l10n.downloadMirror),
              subtitle: Text(
                _githubMirrorController.text.isEmpty
                    ? l10n.mirrorNotConfigured
                    : _githubMirrorController.text,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showGithubMirrorDialog,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.aboutApp),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAboutPage,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearanceSection() {
    final l10n = AppLocalizations.of(context)!;
    return _SectionCard(
      icon: Icons.tune,
      title: l10n.general,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final locale = ref.watch(appLocaleProvider);
            return ListTile(
              leading: const Icon(Icons.language_outlined),
              title: Text(l10n.language),
              subtitle: Text(
                locale.languageCode == 'en' ? l10n.english : l10n.chinese,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showLanguagePicker(locale),
            );
          },
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(l10n.themeAndColors),
          subtitle: Text(l10n.themeAndColorsDescription,
              style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ThemeSettingsPage(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRuntimeInstallPanel(AppLocalizations l10n) {
    return ListTile(
      leading: Icon(
        _linuxLikeAvailable ? Icons.check_circle_outline : Icons.info_outline,
        color: _linuxLikeAvailable ? Colors.green : null,
      ),
      title: Text(l10n.linuxLikeExperimental),
      subtitle: Text(
        _linuxLikeAvailable ? l10n.runtimeInstalled : l10n.runtimeNotInstalled,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: _showRuntimeInstallDialog,
    );
  }

  Future<void> _showLanguagePicker(Locale locale) async {
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final labels = AppLocalizations.of(sheetContext)!;
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(locale.languageCode == 'zh'
                    ? Icons.check_rounded
                    : Icons.language_outlined),
                title: Text(labels.chinese),
                onTap: () => Navigator.pop(sheetContext, const Locale('zh')),
              ),
              ListTile(
                leading: Icon(locale.languageCode == 'en'
                    ? Icons.check_rounded
                    : Icons.language_outlined),
                title: Text(labels.english),
                onTap: () => Navigator.pop(sheetContext, const Locale('en')),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null && selected.languageCode != locale.languageCode) {
      await ref.read(appLocaleProvider.notifier).setLocale(selected);
    }
  }
}
