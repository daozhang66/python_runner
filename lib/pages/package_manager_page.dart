import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/packages/application/package_controller.dart';
import '../features/packages/application/package_state.dart';
import '../models/package_info.dart';
import '../runtime/runtime_package.dart';
import '../services/native_bridge.dart';
import '../ui/app_badges.dart';
import '../ui/app_design_tokens.dart';
import '../ui/app_empty_state.dart';
import '../ui/app_state_views.dart';
import '../ui/app_skeleton.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_surfaces.dart';
import '../ui/app_toolbars.dart';
import '../widgets/confirm_dialog.dart';
import 'app_file_picker_page.dart';

class PackageManagerPage extends ConsumerStatefulWidget {
  const PackageManagerPage({super.key});

  @override
  ConsumerState<PackageManagerPage> createState() => _PackageManagerPageState();
}

class _PackageManagerPageState extends ConsumerState<PackageManagerPage>
    with SingleTickerProviderStateMixin {
  final _bridge = NativeBridge();
  final _packageController = TextEditingController();
  final _versionController = TextEditingController();
  final _searchController = TextEditingController();
  late final TabController _tabController;
  String _searchQuery = '';
  String? _indexUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(
          () => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    Future.microtask(() {
      ref.read(packageControllerProvider.notifier).ensureLoaded();
      _loadIndexUrl();
    });
  }

  Future<void> _loadIndexUrl() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _indexUrl = prefs.getString('pypi_index_url');
    });
  }

  void _install() {
    final name = _packageController.text.trim();
    if (name.isEmpty) return;
    final version = _versionController.text.trim();
    ref.read(packageControllerProvider.notifier).install(
          name,
          version: version.isEmpty ? null : version,
          indexUrl: _indexUrl,
        );
    _packageController.clear();
    _versionController.clear();
  }

  Future<void> _installRequirementsFromFile(PackageState state) async {
    if (!state.supportsRequirementsInstall) {
      _showSnack(AppLocalizations.of(context)!.requirementsLinuxOnly);
      return;
    }
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: AppLocalizations.of(context)!.installRequirements,
      exactFileName: 'requirements.txt',
    );
    if (selected == null) return;

    String fileName;
    List<int>? bytes;
    if (selected.useSystemPicker) {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      fileName = file.name;
      bytes = file.bytes;
    } else {
      fileName = selected.name;
      bytes = await _bridge.readFilePickerFile(selected.path);
    }

    if (!mounted) return;

    if (fileName.toLowerCase() != 'requirements.txt') {
      _showSnack(AppLocalizations.of(context)!.selectRequirements);
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _showSnack(AppLocalizations.of(context)!.emptyRequirements);
      return;
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    if (content.trim().isEmpty) {
      _showSnack(AppLocalizations.of(context)!.emptyRequirementsShort);
      return;
    }
    await ref
        .read(packageControllerProvider.notifier)
        .installRequirementsFromContent(
          content: content,
          displayName: fileName,
          indexUrl: _indexUrl,
        );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _copyInstallLog(BuildContext context, List<String> log) {
    Clipboard.setData(ClipboardData(text: log.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.installLogCopied),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  _InstallResult? _getInstallResult(List<String> log) {
    if (log.isEmpty) return null;
    final last = log.last;
    if (last.contains('安装成功') || last.contains('修复成功')) {
      return _InstallResult.success;
    }
    if (last.contains('安装失败') ||
        last.contains('修复失败') ||
        last.contains('Error')) {
      return _InstallResult.error;
    }
    return null;
  }

  bool _matchesSearch(String name) =>
      _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery);

  String _buildUninstallMessage(
    String packageName,
    PackageUninstallResult result,
  ) {
    if (!result.success) {
      return result.message.isNotEmpty
          ? result.message
          : AppLocalizations.of(context)!.packageUninstallFailed(packageName);
    }
    if (result.removedDependencies.isEmpty) {
      return AppLocalizations.of(context)!.packageUninstalled(packageName);
    }
    return AppLocalizations.of(context)!.packageUninstalledDependencies(
      packageName,
      result.removedDependencies.join('、'),
    );
  }

  Future<void> _repairPackage(
    WidgetRef ref,
    PackageInfo pkg,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: AppLocalizations.of(context)!.repairPackage,
      content: AppLocalizations.of(context)!.repairPackageConfirm(pkg.name),
      confirmText: AppLocalizations.of(context)!.repair,
      confirmColor: Theme.of(context).colorScheme.primary,
    );
    if (!confirmed || !mounted) return;
    await ref.read(packageControllerProvider.notifier).repair(
          pkg.name,
          version: pkg.version,
          indexUrl: _indexUrl,
        );
  }

  @override
  Widget build(BuildContext context) {
    // 选择性监听：列表/加载/安装/日志分别 select，避免单条日志变化重建整页。
    final packages = ref.watch(
      packageControllerProvider.select((s) => s.packages),
    );
    final isInitialLoading = ref.watch(
      packageControllerProvider.select((s) => s.isInitialLoading),
    );
    final isRefreshing = ref.watch(
      packageControllerProvider.select((s) => s.isRefreshing),
    );
    final loadError = ref.watch(
      packageControllerProvider.select((s) => s.loadError),
    );
    final isInstalling = ref.watch(
      packageControllerProvider.select((s) => s.isInstalling),
    );
    final installLog = ref.watch(
      packageControllerProvider.select((s) => s.installLog),
    );
    final supportsRequirementsInstall = ref.watch(
      packageControllerProvider.select((s) => s.supportsRequirementsInstall),
    );

    final state = PackageState(
      packages: packages,
      isInitialLoading: isInitialLoading,
      isRefreshing: isRefreshing,
      loadError: loadError,
      isInstalling: isInstalling,
      installLog: installLog,
      supportsRequirementsInstall: supportsRequirementsInstall,
    );

    final localizations = AppLocalizations.of(context)!;

    final userPackages = packages
        .where((p) => p.isUserPackage && _matchesSearch(p.name))
        .toList();
    final builtinPackages = packages
        .where((p) => !p.isUserPackage && _matchesSearch(p.name))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          localizations.packageManager,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _buildInstallPanel(state),
          if (isRefreshing) const LinearProgressIndicator(minHeight: 2),
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: localizations.userPackages(userPackages.length)),
                    Tab(
                        text: localizations
                            .builtInPackages(builtinPackages.length)),
                  ],
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          Expanded(
            child: isInitialLoading
                ? const AppListSkeleton()
                : loadError != null && packages.isEmpty
                    ? AppErrorState(
                        message: localizations.loadPackagesFailed,
                        retryLabel: localizations.retry,
                        onRetry: () => ref
                            .read(packageControllerProvider.notifier)
                            .refresh(),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPackageList(context, userPackages,
                              canDelete: true),
                          _buildPackageList(context, builtinPackages,
                              canDelete: false),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallPanel(PackageState state) {
    final result = _getInstallResult(state.installLog);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardSurface(colors),
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactInstallFields(state),
          if (state.isInstalling)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (state.installLog.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildCompactInstallLog(state, result),
            ),
          const SizedBox(height: 6),
          _buildSearchAndRefreshRow(state),
        ],
      ),
    );
  }

  Widget _buildCompactInstallLog(
    PackageState state,
    _InstallResult? result,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final statusBadge = !state.isInstalling && result != null
        ? AppStatusBadge(
            label: result == _InstallResult.success
                ? l10n.installSuccess
                : l10n.error,
            tone: result == _InstallResult.success
                ? AppBadgeTone.success
                : AppBadgeTone.error,
          )
        : AppStatusBadge(label: l10n.installing, tone: AppBadgeTone.info);

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppThemeColors.softSurface(colors),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          statusBadge,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.installLog.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            visualDensity: VisualDensity.compact,
            onPressed: () => _copyInstallLog(context, state.installLog),
            tooltip: l10n.copyLog,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndRefreshRow(PackageState state) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: AppSearchBar(
            controller: _searchController,
            hintText: l10n.searchInstalledPackages,
            onChanged: (v) =>
                setState(() => _searchQuery = v.trim().toLowerCase()),
            onClear: () => _searchController.clear(),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: state.isRefreshing
                ? null
                : () => ref.read(packageControllerProvider.notifier).refresh(),
            visualDensity: VisualDensity.compact,
            tooltip: l10n.refresh,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactInstallFields(PackageState state) {
    final l10n = AppLocalizations.of(context)!;
    final requirementsTooltip = state.supportsRequirementsInstall
        ? l10n.installRequirements
        : l10n.requirementsLinuxOnly;
    return Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: Icon(Icons.add_box_outlined,
              size: 22, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _packageController,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: l10n.packageName,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onSubmitted: (_) => _install(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 82, height: 38, child: _buildVersionField()),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          height: 38,
          child: Tooltip(
            message: requirementsTooltip,
            child: IconButton(
              icon: const Icon(Icons.description_outlined, size: 20),
              onPressed:
                  state.isInstalling || !state.supportsRequirementsInstall
                      ? null
                      : () => _installRequirementsFromFile(state),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          height: 38,
          child: FilledButton(
            onPressed: state.isInstalling ? null : _install,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.install),
          ),
        ),
      ],
    );
  }

  Widget _buildVersionField() {
    return TextField(
      controller: _versionController,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.version,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onSubmitted: (_) => _install(),
    );
  }

  Widget _buildPackageList(
    BuildContext context,
    List<PackageInfo> packages, {
    required bool canDelete,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (packages.isEmpty) {
      return AppEmptyState(
        icon: Icons.inventory_2_outlined,
        title:
            _searchQuery.isNotEmpty ? l10n.noMatchingPackages : l10n.noPackages,
        subtitle: canDelete
            ? l10n.installPythonPackage
            : l10n.noBuiltinPackagesReturned,
      );
    }

    return ListView.builder(
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final pkg = packages[index];
        return _buildPackageListTile(
          context,
          pkg,
          canDelete: canDelete,
        );
      },
    );
  }

  Widget _buildPackageListTile(
    BuildContext context,
    PackageInfo pkg, {
    required bool canDelete,
  }) {
    final subtitle = _formatPackageSubtitle(pkg);
    final isInstalling = ref.watch(
      packageControllerProvider.select((s) => s.isInstalling),
    );

    return AppSurface(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        dense: true,
        title: Text(pkg.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pkg.hasBrokenIntegrity) ...[
              Tooltip(
                message: pkg.integrityMessage.isEmpty
                    ? AppLocalizations.of(context)!.packageMissing
                    : pkg.integrityMessage,
                child: AppStatusBadge(
                  label: AppLocalizations.of(context)!.damaged,
                  tone: AppBadgeTone.error,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 4),
            ],
            AppStatusBadge(
              label: pkg.isUserPackage
                  ? AppLocalizations.of(context)!.user
                  : AppLocalizations.of(context)!.builtIn,
              tone:
                  pkg.isUserPackage ? AppBadgeTone.info : AppBadgeTone.neutral,
            ),
            if (canDelete) ...[
              const SizedBox(width: 4),
              if (pkg.hasBrokenIntegrity) ...[
                IconButton(
                  icon: const Icon(Icons.build_outlined, size: 20),
                  onPressed:
                      isInstalling ? null : () => _repairPackage(ref, pkg),
                  visualDensity: VisualDensity.compact,
                  tooltip: AppLocalizations.of(context)!.reinstallRepair,
                ),
                const SizedBox(width: 2),
              ],
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final confirmed = await ConfirmDialog.show(
                    context,
                    title: AppLocalizations.of(context)!.uninstallPackage,
                    content: AppLocalizations.of(context)!
                        .uninstallPackageConfirm(pkg.name),
                    confirmText: AppLocalizations.of(context)!.uninstall,
                    confirmColor: Theme.of(context).colorScheme.error,
                  );
                  if (!confirmed || !context.mounted) return;

                  final result = await ref
                      .read(packageControllerProvider.notifier)
                      .uninstall(pkg.name);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_buildUninstallMessage(pkg.name, result)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatVersionLabel(String version) {
    final value = version.trim();
    if (value.isEmpty || value.toLowerCase() == 'unknown') {
      return AppLocalizations.of(context)!.unknownVersion;
    }
    return value;
  }

  String _formatPackageSubtitle(PackageInfo pkg) {
    final versionLabel = _formatVersionLabel(pkg.version);
    if (!pkg.hasBrokenIntegrity || pkg.integrityMessage.trim().isEmpty) {
      return versionLabel;
    }
    return '$versionLabel · ${pkg.integrityMessage.trim()}';
  }

  @override
  void dispose() {
    _packageController.dispose();
    _versionController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
}

enum _InstallResult { success, error }
