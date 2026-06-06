import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/package_info.dart';
import '../providers/package_provider.dart';
import '../runtime/runtime_package.dart';
import '../widgets/confirm_dialog.dart';

class PackageManagerPage extends StatefulWidget {
  const PackageManagerPage({super.key});

  @override
  State<PackageManagerPage> createState() => _PackageManagerPageState();
}

class _PackageManagerPageState extends State<PackageManagerPage>
    with SingleTickerProviderStateMixin {
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
      packageProvider.loadPackages();
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
    final installResult = _getInstallResult(provider.installLog);

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
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _packageController,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: '包名 (如 requests)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _install(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _versionController,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: '版本',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: provider.installing ? null : _install,
                      child: const Text('安装'),
                    ),
                  ],
                ),
                if (provider.installing) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
                if (provider.installLog.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (!provider.installing && installResult != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: installResult == _InstallResult.success
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: installResult == _InstallResult.success
                              ? Colors.green.withValues(alpha: 0.4)
                              : Colors.red.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            installResult == _InstallResult.success
                                ? Icons.check_circle
                                : Icons.error,
                            size: 18,
                            color: installResult == _InstallResult.success
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              provider.installLog.last,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: installResult == _InstallResult.success
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 100),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Stack(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          reverse: true,
                          itemCount: provider.installLog.length,
                          itemBuilder: (_, i) => SelectableText(
                            provider
                                .installLog[provider.installLog.length - 1 - i],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () =>
                                _copyInstallLog(context, provider.installLog),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _searchController,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: '搜索已安装的库...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
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
                onPressed: () => provider.loadPackages(),
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

  Widget _buildPackageList(
    BuildContext context,
    List<PackageInfo> packages,
    PackageProvider provider, {
    required bool canDelete,
  }) {
    if (packages.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? '未找到匹配的库' : '暂无',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final pkg = packages[index];
        return ListTile(
          dense: true,
          title: Text(pkg.name),
          subtitle: Text(pkg.version, style: const TextStyle(fontSize: 12)),
          trailing: canDelete
              ? IconButton(
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
                )
              : null,
        );
      },
    );
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
