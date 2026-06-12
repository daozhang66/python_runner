import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/package_info.dart';
import '../providers/package_provider.dart';
import '../runtime/runtime_package.dart';
import '../services/native_bridge.dart';
import '../ui/app_badges.dart';
import '../ui/app_design_tokens.dart';
import '../ui/app_empty_state.dart';
import '../ui/app_surfaces.dart';
import '../ui/app_toolbars.dart';
import '../widgets/confirm_dialog.dart';
import 'app_file_picker_page.dart';

class PackageManagerPage extends StatefulWidget {
  const PackageManagerPage({super.key});

  @override
  State<PackageManagerPage> createState() => _PackageManagerPageState();
}

class _PackageManagerPageState extends State<PackageManagerPage>
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
    final packageProvider = context.read<PackageProvider>();
    Future.microtask(() {
      packageProvider.ensurePackagesLoaded();
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
    context.read<PackageProvider>().installPackage(
          name,
          version: version.isEmpty ? null : version,
          indexUrl: _indexUrl,
        );
    _packageController.clear();
    _versionController.clear();
  }

  Future<void> _installRequirementsFromFile(PackageProvider provider) async {
    if (!provider.supportsRequirementsInstall) {
      _showSnack('requirements.txt 仅支持 Linux-like');
      return;
    }
    final selected = await AppFilePickerPage.pickFile(
      context,
      title: '安装 requirements.txt',
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

    if (fileName.toLowerCase() != 'requirements.txt') {
      _showSnack('请选择 requirements.txt');
      return;
    }
    if (bytes == null || bytes.isEmpty) {
      _showSnack('requirements.txt 为空或无法读取');
      return;
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    if (content.trim().isEmpty) {
      _showSnack('requirements.txt 为空');
      return;
    }
    await provider.installRequirementsFromContent(
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
      const SnackBar(content: Text('已复制安装日志'), duration: Duration(seconds: 1)),
    );
  }

  _InstallResult? _getInstallResult(List<String> log) {
    if (log.isEmpty) return null;
    final last = log.last;
    if (last.contains('安装成功')) return _InstallResult.success;
    if (last.contains('安装失败') || last.contains('Error')) {
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
      return result.message.isNotEmpty ? result.message : '$packageName 卸载失败';
    }
    if (result.removedDependencies.isEmpty) {
      return '$packageName 已卸载';
    }
    return '$packageName 已卸载，并清理 ${result.removedDependencies.join('、')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PackageProvider>();
    final packages = provider.packages;

    final userPackages = packages
        .where((p) => p.isUserPackage && _matchesSearch(p.name))
        .toList();
    final builtinPackages = packages
        .where((p) => !p.isUserPackage && _matchesSearch(p.name))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '库管理',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          _buildInstallPanel(provider),
          if (provider.loadingPackages)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppSearchBar(
              controller: _searchController,
              hintText: '搜索已安装的库...',
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
              onClear: () => _searchController.clear(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: '用户安装 (${userPackages.length})'),
                    Tab(text: '内置库 (${builtinPackages.length})'),
                  ],
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: provider.loadingPackages
                    ? null
                    : () => provider.loadPackages(forceRefresh: true),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPackageList(context, userPackages, provider,
                    canDelete: true),
                _buildPackageList(context, builtinPackages, provider,
                    canDelete: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallPanel(PackageProvider provider) {
    final result = _getInstallResult(provider.installLog);
    final colors = Theme.of(context).colorScheme;

    return AppSectionCard(
      icon: Icons.add_box_outlined,
      title: '安装库',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: _buildCompactInstallFields(provider),
        ),
        if (provider.installing)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (provider.installLog.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!provider.installing && result != null)
                      AppStatusBadge(
                        label: result == _InstallResult.success ? '成功' : '失败',
                        tone: result == _InstallResult.success
                            ? AppBadgeTone.success
                            : AppBadgeTone.error,
                      )
                    else
                      const AppStatusBadge(
                        label: '安装中',
                        tone: AppBadgeTone.info,
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _copyInstallLog(context, provider.installLog),
                      tooltip: '复制日志',
                    ),
                  ],
                ),
                Container(
                  constraints: const BoxConstraints(maxHeight: 72),
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppThemeColors.softSurface(colors),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    provider.installLog.reversed.take(3).join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCompactInstallFields(PackageProvider provider) {
    final requirementsTooltip = provider.supportsRequirementsInstall
        ? '安装 requirements.txt'
        : 'requirements.txt 仅支持 Linux-like';
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _packageController,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              hintText: '包名',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
            onSubmitted: (_) => _install(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 88, child: _buildVersionField()),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          height: 40,
          child: Tooltip(
            message: requirementsTooltip,
            child: IconButton(
              icon: const Icon(Icons.description_outlined, size: 20),
              onPressed:
                  provider.installing || !provider.supportsRequirementsInstall
                      ? null
                      : () => _installRequirementsFromFile(provider),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          height: 40,
          child: FilledButton(
            onPressed: provider.installing ? null : _install,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('安装'),
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
      decoration: const InputDecoration(
        hintText: '版本',
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      onSubmitted: (_) => _install(),
    );
  }

  Widget _buildPackageList(
    BuildContext context,
    List<PackageInfo> packages,
    PackageProvider provider, {
    required bool canDelete,
  }) {
    if (packages.isEmpty) {
      return AppEmptyState(
        icon: Icons.inventory_2_outlined,
        title: _searchQuery.isNotEmpty ? '未找到匹配的库' : '暂无库',
        subtitle: canDelete ? '可在上方安装 Python 包' : '当前运行环境未返回内置库',
      );
    }

    return ListView.builder(
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final pkg = packages[index];
        return _buildPackageListTile(
          context,
          pkg,
          provider,
          canDelete: canDelete,
        );
      },
    );
  }

  Widget _buildPackageListTile(
    BuildContext context,
    PackageInfo pkg,
    PackageProvider provider, {
    required bool canDelete,
  }) {
    final versionLabel = _formatVersionLabel(pkg.version);

    return AppSurface(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        dense: true,
        title: Text(pkg.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(versionLabel, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStatusBadge(
              label: pkg.isUserPackage ? '用户' : '内置',
              tone:
                  pkg.isUserPackage ? AppBadgeTone.info : AppBadgeTone.neutral,
            ),
            if (canDelete) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final confirmed = await ConfirmDialog.show(
                    context,
                    title: '卸载库',
                    content: '确定要卸载 "${pkg.name}" 吗？',
                    confirmText: '卸载',
                    confirmColor: Theme.of(context).colorScheme.error,
                  );
                  if (!confirmed || !context.mounted) return;

                  final result = await provider.uninstallPackage(pkg.name);
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
      return '版本未知';
    }
    return value;
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
