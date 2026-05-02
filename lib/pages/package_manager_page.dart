import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/package_provider.dart';
import '../widgets/confirm_dialog.dart';

/// Packages bundled at build time — cannot be uninstalled at runtime.
const _builtinPackages = {
  'pip', 'setuptools', 'wheel',
  // 网络
  'aiohttp', 'requests', 'httpx', 'beautifulsoup4', 'pyjwt',
  'certifi', 'urllib3', 'chardet',
  // 数据处理
  'ujson', 'marshmallow', 'python-dateutil', 'pytz',
  // 加密与底层
  'pycryptodome', 'cffi', 'six', 'cryptography',
  'pyDes', 'rsa', 'pyasn1',
  // 数据库
  'tinydb', 'peewee', 'pymysql', 'redis',
  // 实用工具
  'loguru', 'tqdm', 'openpyxl', 'python-docx', 'et-xmlfile',
  // YAML
  'PyYAML', 'ruamel.yaml', 'ruamel.yaml.clib',
  // 科学计算
  'numpy', 'pandas', 'pillow', 'lxml', 'sqlalchemy',
  'scipy', 'matplotlib', 'scikit-learn', 'opencv-python',
  // 移动端与自动化
  'plyer', 'schedule',
  // 依赖包
  'aiosignal', 'async-timeout', 'attrs', 'multidict', 'yarl', 'frozenlist',
  'idna', 'charset-normalizer', 'soupsieve', 'typing-extensions', 'packaging',
  'anyio', 'sniffio', 'exceptiongroup', 'httpcore', 'h11',
  'pycparser', 'contourpy', 'cycler', 'fonttools', 'kiwisolver', 'pyparsing',
  'joblib', 'threadpoolctl',
  'chaquopy-libffi', 'chaquopy-openblas', 'chaquopy-libgfortran',
  'chaquopy-libcxx', 'chaquopy-freetype', 'chaquopy-libjpeg',
  'chaquopy-libpng', 'chaquopy-libxml2', 'chaquopy-libxslt',
  'chaquopy-libomp',
};

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
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    Future.microtask(() {
      context.read<PackageProvider>().loadPackages();
      _loadIndexUrl();
    });
  }

  Future<void> _loadIndexUrl() async {
    final prefs = await SharedPreferences.getInstance();
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
    if (last.contains('安装失败') || last.contains('Error')) return _InstallResult.error;
    return null;
  }

  static final _builtinNormalized = _builtinPackages
      .map((n) => n.toLowerCase().replaceAll('-', '_'))
      .toSet();

  bool _isBuiltin(String name) =>
      _builtinNormalized.contains(name.toLowerCase().replaceAll('-', '_'));

  bool _matchesSearch(String name) =>
      _searchQuery.isEmpty || name.toLowerCase().contains(_searchQuery);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PackageProvider>();
    final packages = provider.packages;
    final installResult = _getInstallResult(provider.installLog);

    final userPackages = packages
        .where((p) => !_isBuiltin(p.name) && _matchesSearch(p.name))
        .toList();
    final builtinPackagesList = packages
        .where((p) => _isBuiltin(p.name) && _matchesSearch(p.name))
        .toList();

    return Scaffold(
      body: Column(
        children: [
          // Install input area
          Container(
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            provider.installLog[provider.installLog.length - 1 - i],
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () => _copyInstallLog(context, provider.installLog),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(Icons.copy, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          // Search bar
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Tab bar + refresh
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: '用户安装 (${userPackages.length})'),
                    Tab(text: '内置库 (${builtinPackagesList.length})'),
                  ],
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // User-installed packages
                _buildPackageList(context, userPackages, provider, canDelete: true),
                // Built-in packages
                _buildPackageList(context, builtinPackagesList, provider, canDelete: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageList(
    BuildContext context,
    List<dynamic> pkgs,
    PackageProvider provider, {
    required bool canDelete,
  }) {
    if (pkgs.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? '未找到匹配的库' : '暂无',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      itemCount: pkgs.length,
      itemBuilder: (context, index) {
        final pkg = pkgs[index];
        return ListTile(
          dense: true,
          title: Text(pkg.name),
          subtitle: Text(
            pkg.version,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: canDelete
              ? IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    final confirmed = await ConfirmDialog.show(
                      context,
                      title: '卸载库',
                      content: '确定要卸载 "${pkg.name}" 吗？',
                      confirmText: '卸载',
                      confirmColor: Theme.of(context).colorScheme.error,
                    );
                    if (!confirmed || !context.mounted) return;
                    final success = await provider.uninstallPackage(pkg.name);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success ? '${pkg.name} 已卸载' : '${pkg.name} 卸载失败'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
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
