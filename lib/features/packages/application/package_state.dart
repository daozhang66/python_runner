import '../../../models/package_info.dart';

/// 包管理不可变状态快照。
///
/// 与迁移前的 legacy ChangeNotifier 行为对齐：首次空数据加载用 [isInitialLoading]，
/// 已有缓存刷新用 [isRefreshing]；安装/卸载/修复进行中用 [isInstalling]；
/// 安装日志在 5 秒后自动清空（由 Controller 调度）。
class PackageState {
  const PackageState({
    this.packages = const [],
    this.isInitialLoading = false,
    this.isRefreshing = false,
    this.isInstalling = false,
    this.loadError,
    this.installLog = const [],
    this.activeBackendId = '',
    this.supportsRequirementsInstall = false,
  });

  /// 已安装包列表（按名称排序）。集合不可变，外部不应直接修改。
  final List<PackageInfo> packages;

  /// 首次加载、且本地无缓存时的全屏 loading。
  final bool isInitialLoading;

  /// 已有数据时的后台刷新（显示进度条，不覆盖列表）。
  final bool isRefreshing;

  /// 安装/修复/requirements 进行中。
  final bool isInstalling;

  /// 加载失败的可展示错误文本；为 null 表示无错误。
  final String? loadError;

  /// 安装/修复日志条目；成功或失败后约 5 秒由 Controller 自动清空。
  final List<String> installLog;

  /// 当前运行引擎后端标识。
  final String activeBackendId;

  /// 是否支持 requirements.txt 批量安装（仅 Linux-like）。
  /// 由 Controller 从 Repository 读取并写入状态，页面只读取本字段。
  final bool supportsRequirementsInstall;

  PackageState copyWith({
    List<PackageInfo>? packages,
    bool? isInitialLoading,
    bool? isRefreshing,
    bool? isInstalling,
    String? loadError,
    bool clearLoadError = false,
    List<String>? installLog,
    String? activeBackendId,
    bool? supportsRequirementsInstall,
  }) {
    return PackageState(
      packages: packages ?? this.packages,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isInstalling: isInstalling ?? this.isInstalling,
      loadError: clearLoadError ? null : (loadError ?? this.loadError),
      installLog: installLog ?? this.installLog,
      activeBackendId: activeBackendId ?? this.activeBackendId,
      supportsRequirementsInstall:
          supportsRequirementsInstall ?? this.supportsRequirementsInstall,
    );
  }
}
