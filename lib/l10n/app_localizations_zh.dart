// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Python运行器';

  @override
  String get settings => '设置';

  @override
  String get language => '语言';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get scriptDetails => '脚本详情';

  @override
  String get selectScript => '选择一个脚本';

  @override
  String get selectScriptDescription => '在左侧列表中选择脚本后可查看详情和快捷操作';

  @override
  String get edit => '编辑';

  @override
  String get run => '运行';

  @override
  String get openConsole => '查看控制台';

  @override
  String get scriptGroup => '分组';

  @override
  String get createdAt => '创建时间';

  @override
  String get lastModified => '最近修改';

  @override
  String get runCount => '运行次数';

  @override
  String get scriptStatus => '状态';

  @override
  String get running => '运行中';

  @override
  String get idle => '空闲';

  @override
  String get pinned => '已置顶';

  @override
  String get regularScript => '普通脚本';

  @override
  String get pin => '置顶';

  @override
  String get unpin => '取消置顶';

  @override
  String get loadingScripts => '正在加载脚本';

  @override
  String get loadingPackages => '正在加载已安装的库';

  @override
  String get loadPackagesFailed => '加载库列表失败';

  @override
  String get retry => '重试';

  @override
  String get enableAutoFollow => '开启自动滚动';

  @override
  String get disableAutoFollow => '关闭自动滚动';

  @override
  String get exportLogs => '导出日志';

  @override
  String get scripts => '脚本';

  @override
  String get network => '网络';

  @override
  String get packageManager => '库管理';

  @override
  String get networkRequests => '网络请求';

  @override
  String get searchUrlOrDomain => '搜索 URL / 域名...';

  @override
  String get showNoiseRequests => '显示 DNS/connect/进程记录';

  @override
  String get hideNoiseRequests => '隐藏 DNS/connect/进程记录';

  @override
  String get filter => '筛选';

  @override
  String get clear => '清空';

  @override
  String get clearFilters => '清除筛选';

  @override
  String get noNetworkRequests => '暂无网络请求记录';

  @override
  String get noMatchingRequests => '无匹配的请求';

  @override
  String get runNetworkScriptHint => '运行包含网络请求的脚本后，请求将自动显示在这里';

  @override
  String get tryClearingFilters => '尝试清空筛选条件';

  @override
  String get update => '更新';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get imagePreview => '图片预览';

  @override
  String get search => '搜索';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get updateNow => '立即更新';

  @override
  String get dontRemind => '不再提示';

  @override
  String get releaseNotes => '更新日志';

  @override
  String fileSize(Object size) {
    return '大小: $size';
  }

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String todayAt(Object time) {
    return '今天 $time';
  }

  @override
  String yesterdayAt(Object time) {
    return '昨天 $time';
  }

  @override
  String get unknownReleaseDate => '发布时间未知';

  @override
  String get updateLog => '更新日志';

  @override
  String get searchVersionOrNotes => '搜索版本或更新内容';

  @override
  String get updateLogLoadFailed => '更新日志加载失败';

  @override
  String openReleaseFailed(Object error) {
    return '打开发布页失败: $error';
  }

  @override
  String get noReleaseLogs => '暂无更新日志';

  @override
  String get noMatchingReleaseLogs => '没有匹配的更新日志';

  @override
  String get unnamedRelease => '未命名版本';

  @override
  String get prerelease => '预发布';

  @override
  String get noReleaseNotes => '当前发布没有填写更新说明。';

  @override
  String get releasePage => '发布页';

  @override
  String get appLogs => '应用日志';

  @override
  String get refresh => '刷新';

  @override
  String get clearLogs => '清空日志';

  @override
  String get searchLogContent => '搜索日志内容';

  @override
  String get noLogs => '暂无日志';

  @override
  String get noMatchingLogs => '没有匹配的日志';

  @override
  String get logsCopied => '日志已复制到剪贴板';

  @override
  String get clearLogsConfirm => '确定要清空所有日志吗？此操作不可恢复。';

  @override
  String get logsCleared => '日志已清空';

  @override
  String get level => '级别';

  @override
  String get source => '来源';

  @override
  String get time => '时间';

  @override
  String get all => '全部';

  @override
  String get lastSevenDays => '最近7天';

  @override
  String get total => '总计';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count小时前';
  }

  @override
  String get install => '安装';

  @override
  String get uninstall => '卸载';

  @override
  String get repair => '修复';

  @override
  String get copyInstallLog => '复制安装日志';

  @override
  String get installLogCopied => '已复制安装日志';

  @override
  String get searchInstalledPackages => '搜索已安装的库...';

  @override
  String get packageName => '包名';

  @override
  String get version => '版本';

  @override
  String get noPackages => '暂无库';

  @override
  String get noMatchingPackages => '未找到匹配的库';

  @override
  String get unknownVersion => '版本未知';

  @override
  String userInstalledPackages(int count) {
    return '用户安装 ($count)';
  }

  @override
  String builtInPackages(int count) {
    return '内置库 ($count)';
  }

  @override
  String get uninstallPackage => '卸载库';

  @override
  String uninstallPackageConfirm(Object name) {
    return '确定要卸载 \"$name\" 吗？';
  }

  @override
  String get pythonRunnerSlogan => '人生苦短，我用 Python';

  @override
  String get terminalTheme => '终端主题';

  @override
  String get darkTerminal => '深色终端';

  @override
  String get lightTerminal => '浅色终端';

  @override
  String get followSystem => '跟随系统';

  @override
  String get monochromeOutput => '黑白输出';

  @override
  String get showLineNumbers => '显示行号';

  @override
  String get hideLineNumbers => '隐藏行号';

  @override
  String get showAll => '显示全部';

  @override
  String get copyAll => '全部复制';

  @override
  String get searchLogs => '搜索日志...';

  @override
  String get onlyErrors => '仅看错误';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get noMatchingOutput => '无匹配输出';

  @override
  String get waitingForOutput => '等待输出...';

  @override
  String get noOutput => '暂无输出';

  @override
  String get newOutputAvailable => '有新输出，点击跳转到底部';

  @override
  String get inputContent => '输入内容...';

  @override
  String get waitingForInput => '等待脚本请求输入...';

  @override
  String get stop => '停止';

  @override
  String get runAgain => '重新运行';

  @override
  String get waitingForInputStatus => '等待输入';

  @override
  String get error => '错误';

  @override
  String get timeout => '超时';

  @override
  String get stopped => '已停止';

  @override
  String get finished => '已结束';

  @override
  String get noRun => '暂无运行';

  @override
  String get logsExported => '日志已导出';

  @override
  String logsExportedTo(Object path) {
    return '日志已导出至 $path';
  }

  @override
  String copiedAllLines(int count) {
    return '已复制全部 $count 行';
  }

  @override
  String get exportFailedTryAgain => '导出失败，请稍后重试';

  @override
  String get manageRuntime => '管理引擎';

  @override
  String get runtimeInstalled => 'Linux-like 运行引擎已安装';

  @override
  String get runtimeNotInstalled => 'Linux-like 运行引擎未安装';

  @override
  String get installRuntime => '安装运行引擎';

  @override
  String get repairRuntime => '修复运行引擎';

  @override
  String get runtimeInstalledSuccess => 'Linux-like 运行引擎安装成功';

  @override
  String get runtimeAbout => '关于 Linux-like 运行引擎';

  @override
  String get runtimeDescription =>
      'Linux-like 运行引擎是一个实验性运行环境，提供完整的 Linux 环境，支持更多 Python 包和工具。\n\n• 包含 Debian 基础系统\n• 预装 Python 3 和 pip\n• 支持编译原生扩展\n• 更好的兼容性';

  @override
  String get preparing => '准备中...';

  @override
  String get processing => '正在处理...';

  @override
  String get runtimeDownloadRequirement =>
      '需要下载约 104MB 的 Debian + Python + pip + build-essential 环境包';

  @override
  String get allFiles => '全部文件';

  @override
  String get back => '返回';

  @override
  String get upOneLevel => '上一级';

  @override
  String get select => '选择';

  @override
  String get internalStorage => '内部存储';

  @override
  String get systemFilePicker => '系统选择文件';

  @override
  String get storageLocations => '存储位置';

  @override
  String searchFiles(Object filter) {
    return '搜索 $filter';
  }

  @override
  String get noBrowsableFiles => '没有可浏览的文件';

  @override
  String noFilesInDirectory(Object filter) {
    return '当前目录没有 $filter';
  }

  @override
  String get systemFilePickerHint => '可以使用右上角系统选择文件兜底。';

  @override
  String get goUpOrInternalStorageHint => '可以返回上一级目录，或回到内部存储。';

  @override
  String get fileManager => '文件管理';

  @override
  String get workDirectory => '工作目录';

  @override
  String get rootDirectory => '根目录';

  @override
  String get switchToRoot => '切换到根目录';

  @override
  String get switchToWorkingDirectory => '切换到工作目录';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get newName => '新名称';

  @override
  String deleteItemConfirm(Object name) {
    return '确定删除“$name”吗？目录必须为空才能删除。';
  }

  @override
  String get noPermissionDirectory => '无权限访问此目录';

  @override
  String get loadDirectoryFailed => '加载目录失败';

  @override
  String get emptyDirectory => '此目录为空';

  @override
  String get searchCurrentDirectory => '搜索当前目录';

  @override
  String get filePreview => '文件预览';

  @override
  String get cannotReadFile => '无法读取此文件';

  @override
  String get unsupportedBinaryFile => '二进制文件，暂不支持查看';

  @override
  String get runtimeEngine => '运行引擎';

  @override
  String get chaquopyDefault => 'Chaquopy（默认）';

  @override
  String get linuxLikeExperimental => 'Linux-like（实验）';

  @override
  String get pypiSource => 'PyPI 源';

  @override
  String get useOfficialSourceWhenEmpty => '留空使用官方源';

  @override
  String get restoreOfficialSource => '恢复官方源';

  @override
  String get script => '脚本';

  @override
  String get executionTimeout => '执行超时时间';

  @override
  String get unlimited => '无限制';

  @override
  String get workingDirectory => '工作目录';

  @override
  String get defaultWorkingDirectory =>
      '默认：/storage/emulated/0/Download/PythonRunner';

  @override
  String get scriptWorkingDirectoryDescription => '脚本运行时的文件读写目录';

  @override
  String get scriptExportDirectory => '脚本导出目录';

  @override
  String get defaultDownloadDirectory => '默认：下载目录';

  @override
  String get networkDebugMode => '网络调试模式';

  @override
  String get networkDebugModeDescription => '开启后可配置代理和证书选项';

  @override
  String get allowInsecureCertificates => '允许不安全证书';

  @override
  String get proxyConfigurationOptional => '代理配置（可选）';

  @override
  String get proxyConfigurationDescription => '填写后网络请求将通过指定代理';

  @override
  String get proxyAddress => '代理地址';

  @override
  String get port => '端口';

  @override
  String get recordNetworkRequests => '记录网络请求';

  @override
  String get recordNetworkRequestsDescription => '捕获 HTTP、DNS、socket 与常见网络命令';

  @override
  String get recordResponsePreview => '记录响应体预览';

  @override
  String get enableRequestOverrides => '启用请求覆盖';

  @override
  String get systemTools => '系统工具';

  @override
  String get exportFullLogs => '导出完整日志';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get autoCheckUpdates => '启动时自动检查更新';

  @override
  String get downloadMirror => '下载加速镜像';

  @override
  String get aboutApp => '关于应用';

  @override
  String get general => '通用';

  @override
  String get themeAndColors => '主题与配色';

  @override
  String get liquidNavigation => '液态玻璃导航栏';

  @override
  String get interfaceStyle => '界面风格';

  @override
  String get classicMaterial => '经典 Material';

  @override
  String get liquidGlass => '液态玻璃';

  @override
  String get navigationStyle => '导航栏风格';

  @override
  String get followInterface => '跟随界面';

  @override
  String get appLogsDescription => '查看和筛选系统日志、崩溃日志、脚本错误';

  @override
  String get exportFullLogsDescription => '导出完整诊断日志到工作目录，未设置则使用默认目录';

  @override
  String get checkForUpdatesDescription => '从 GitHub Releases 获取最新 APK';

  @override
  String get updateLogDescription => '查看 GitHub Releases 历史版本';

  @override
  String get autoCheckUpdatesDescription => '每次启动应用时自动检查更新';

  @override
  String get mirrorNotConfigured => '未设置（点击配置）';

  @override
  String get themeAndColorsDescription => '主题模式、Material You、配色方案、自定义颜色、字体';

  @override
  String hours(Object value) {
    return '$value 小时';
  }

  @override
  String minutes(Object value) {
    return '$value 分钟';
  }

  @override
  String seconds(Object value) {
    return '$value 秒';
  }

  @override
  String get requestOverrideWarning =>
      '开启后将全局覆盖 Python 脚本中 HTTP 请求的 User-Agent、Headers、Cookie、超时等设置。\n\n这会修改脚本的实际网络行为，仅建议在调试时使用。';

  @override
  String get confirmEnable => '确认启用';

  @override
  String get saved => '已保存';

  @override
  String get save => '保存';

  @override
  String get unsaved => '未保存';

  @override
  String get synced => '已同步';

  @override
  String get modified => '已修改';

  @override
  String get readOnly => '只读';

  @override
  String get editorActions => '编辑操作';

  @override
  String get indent => '缩进';

  @override
  String get outdent => '反缩进';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get enterEditMode => '进入编辑';

  @override
  String get switchToReadOnly => '切到只读';

  @override
  String get fullScreenTerminal => '全屏终端';

  @override
  String get openingScript => '正在打开脚本';

  @override
  String get more => '更多';

  @override
  String get runProject => '运行项目';

  @override
  String get newFile => '新建文件';

  @override
  String get newDirectory => '新建目录';

  @override
  String get create => '创建';

  @override
  String get rename => '重命名';

  @override
  String get delete => '删除';

  @override
  String get fileCreated => '已创建';

  @override
  String get createFailed => '创建失败';

  @override
  String get renamed => '已重命名';

  @override
  String get renameFailed => '重命名失败';

  @override
  String get deleted => '已删除';

  @override
  String get deleteFailed => '删除失败';

  @override
  String get deleteFile => '删除文件';

  @override
  String get deleteDirectory => '删除目录';

  @override
  String deletePathConfirm(Object path) {
    return '确定要删除「$path」吗？';
  }

  @override
  String get installRequirements => '安装 requirements.txt';

  @override
  String get requirementsLinuxOnly => 'requirements.txt 仅支持 Linux-like';

  @override
  String get selectRequirements => '请选择 requirements.txt';

  @override
  String get emptyRequirements => 'requirements.txt 为空或无法读取';

  @override
  String get emptyRequirementsShort => 'requirements.txt 为空';

  @override
  String userPackages(int count) {
    return '用户安装 ($count)';
  }

  @override
  String get installing => '安装中';

  @override
  String get copyLog => '复制日志';

  @override
  String get packageMissing => '包文件缺失';

  @override
  String get damaged => '损坏';

  @override
  String get user => '用户';

  @override
  String get builtIn => '内置';

  @override
  String get reinstallRepair => '重新安装修复';

  @override
  String get addScript => '添加脚本';

  @override
  String get addGroup => '添加分组';

  @override
  String get newProject => '新建项目';

  @override
  String get importProjectZip => '导入项目 ZIP';

  @override
  String get searchScripts => '搜索脚本';

  @override
  String get listView => '列表视图';

  @override
  String get gridView => '宫格视图';

  @override
  String get reorderScripts => '排序脚本';

  @override
  String get multiSelect => '多选管理';

  @override
  String get showScriptNames => '显示脚本名';

  @override
  String get hideScriptNames => '隐藏脚本名';

  @override
  String get searchScriptsHint => '搜索脚本...';

  @override
  String get noMatches => '无匹配结果';

  @override
  String get noScripts => '还没有脚本';

  @override
  String get createScriptFromMenu => '通过右上角菜单创建脚本';

  @override
  String get tryOtherKeywords => '尝试其他关键词';

  @override
  String get requestDetailsCopied => '已复制请求详情';

  @override
  String get overview => '概览';

  @override
  String requestHeaders(int count) {
    return '请求头 ($count)';
  }

  @override
  String get requestBody => '请求体';

  @override
  String get response => '响应';

  @override
  String responseHeaders(int count) {
    return '响应头 ($count)';
  }

  @override
  String get responseImage => '响应图片';

  @override
  String get responseMedia => '响应媒体';

  @override
  String get responsePreview => '响应体预览';

  @override
  String get responseBody => '响应体';

  @override
  String get viewOriginalImage => '查看原图';

  @override
  String get viewFullContent => '查看完整内容';

  @override
  String get timeLabel => '时间';

  @override
  String get method => '方法';

  @override
  String get library => '库';

  @override
  String get duration => '耗时';

  @override
  String get proxy => '代理';

  @override
  String get sslVerification => 'SSL 校验';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get statusCode => '状态码';

  @override
  String get errorType => '错误类型';

  @override
  String get errorMessage => '错误信息';

  @override
  String get mainProgramUpdateFailed => '主程序更新失败';

  @override
  String get mainProgramSet => '已设置主程序';

  @override
  String get mainProgramNotSet => '已暂不设置主程序';

  @override
  String get unableToReadZipPath => '无法读取 ZIP 路径';

  @override
  String get importFailed => '导入失败';

  @override
  String get zipImportComplete => 'ZIP 导入完成';

  @override
  String get exportFailed => '导出失败';

  @override
  String exportedTo(Object path) {
    return '已导出: $path';
  }

  @override
  String get linuxLikeOnly => '仅 Linux-like 可用';

  @override
  String get installTaskInProgress => '安装任务进行中';

  @override
  String get projectRequirementsLinuxOnly => 'requirements.txt 仅支持 Linux-like';

  @override
  String get installAlreadyInProgress => '已有安装任务进行中，请稍后再试';

  @override
  String get loading => '正在加载';

  @override
  String get projectLaunchFailed => '项目启动失败';

  @override
  String get exportProjectZip => '导出项目 ZIP';

  @override
  String get setMainProgram => '设置主程序';

  @override
  String get installDependencies => '安装依赖';

  @override
  String get waitingForInstallLog => '等待安装日志...';

  @override
  String get installationComplete => '安装完成';

  @override
  String get installationCompleteRefreshingPackages => '安装完成，正在刷新库列表...';

  @override
  String get close => '关闭';

  @override
  String get projectRootDirectory => '项目根目录';

  @override
  String itemsCount(int count) {
    return '$count 项';
  }

  @override
  String get noFilesInProject => '项目里还没有文件';

  @override
  String get currentDirectoryEmpty => '当前目录为空';

  @override
  String get mainProgram => '主程序';

  @override
  String invalidPath(Object error) {
    return '路径无效: $error';
  }

  @override
  String get selectMainProgram => '选择主程序';

  @override
  String get searchPythonFiles => '搜索 .py 文件';

  @override
  String get noPythonFilesFound => '没有发现 .py 文件';

  @override
  String get recommended => '推荐';

  @override
  String get enterMainProgramPath => '手动输入: package/main.py';

  @override
  String get doNotSet => '暂不设置';

  @override
  String get installSuccess => '成功';

  @override
  String installFailed(Object error) {
    return '安装失败: $error';
  }

  @override
  String packageUninstallFailed(Object name) {
    return '$name 卸载失败';
  }

  @override
  String packageUninstalled(Object name) {
    return '$name 已卸载';
  }

  @override
  String packageUninstalledDependencies(Object name, Object dependencies) {
    return '$name 已卸载，并清理 $dependencies';
  }

  @override
  String get repairPackage => '修复库';

  @override
  String repairPackageConfirm(Object name) {
    return '将重新安装 \"$name\"，可能需要网络连接。';
  }

  @override
  String get installPythonPackage => '可在上方安装 Python 包';

  @override
  String get noBuiltinPackagesReturned => '当前运行环境未返回内置库';

  @override
  String get themeMode => '主题模式';

  @override
  String get selectThemeMode => '选择主题模式';

  @override
  String get selectNavigationStyle => '选择导航栏风格';

  @override
  String get light => '浅色';

  @override
  String get dark => '深色';

  @override
  String get materialYouWallpaper => '跟随系统壁纸动态取色';

  @override
  String get materialYouOn => 'Android 12+ · 已启用，配色方案将跟随壁纸';

  @override
  String get materialYouOff => 'Android 12+ · 关闭后可使用下方自定义配色';

  @override
  String get presetThemes => '预设主题';

  @override
  String get moreColors => '更多颜色';

  @override
  String get deleteColor => '删除颜色';

  @override
  String get deleteColorConfirm => '确定要删除这个自定义颜色吗？';

  @override
  String get color => '颜色';

  @override
  String get blue => '蓝色';

  @override
  String get purple => '紫色';

  @override
  String get green => '绿色';

  @override
  String get orange => '橙色';

  @override
  String get pink => '粉色';

  @override
  String get teal => '青色';

  @override
  String get red => '红色';

  @override
  String get indigo => '靛蓝';

  @override
  String get amber => '琥珀';

  @override
  String get advancedOptions => '高级选项';

  @override
  String get colorSchemeAlgorithm => '配色算法';

  @override
  String get blurEffect => '毛玻璃效果';

  @override
  String get blurEffectDescription => '为对话框启用毛玻璃背景模糊效果（需要配色算法支持）';

  @override
  String get font => '字体';

  @override
  String get selectColorSchemeAlgorithm => '选择配色算法';

  @override
  String get selectFont => '选择字体';

  @override
  String get hue => '色相';

  @override
  String get saturation => '饱和度';

  @override
  String get lightness => '亮度';

  @override
  String get variantTonalSpot => '柔和色调（推荐）';

  @override
  String get variantFidelity => '高保真';

  @override
  String get variantContent => '内容优先';

  @override
  String get variantMonochrome => '单色';

  @override
  String get variantNeutral => '中性';

  @override
  String get variantVibrant => '鲜艳';

  @override
  String get variantExpressive => '表现力';

  @override
  String get variantRainbow => '彩虹';

  @override
  String get variantFruitSalad => '水果沙拉';

  @override
  String get variantTonalSpotDescription => '平衡的柔和色调，适合大多数场景';

  @override
  String get variantFidelityDescription => '高度保真原始颜色，最接近种子色';

  @override
  String get variantContentDescription => '强调内容可读性的配色';

  @override
  String get variantMonochromeDescription => '极简单色配色，黑白灰为主';

  @override
  String get variantNeutralDescription => '中性低饱和度配色';

  @override
  String get variantVibrantDescription => '鲜艳高饱和度配色';

  @override
  String get variantExpressiveDescription => '富有表现力的大胆配色';

  @override
  String get variantRainbowDescription => '彩虹般的多彩配色';

  @override
  String get variantFruitSaladDescription => '水果沙拉般的丰富配色';

  @override
  String get add => '添加';

  @override
  String get selectColor => '选择颜色';

  @override
  String get themeOcean => '海蓝';

  @override
  String get themeMint => '薄荷';

  @override
  String get themeLilac => '丁香紫';

  @override
  String get themeHighContrast => '高对比';

  @override
  String runFailed(Object error) {
    return '运行失败: $error';
  }

  @override
  String get modifiedAtUnknown => '改动时间未知';

  @override
  String modifiedAt(Object time) {
    return '改动 $time';
  }

  @override
  String get readOnlyMode => '只读';

  @override
  String get editingMode => '编辑';

  @override
  String get previous => '上一个';

  @override
  String get next => '下一个';

  @override
  String get ungrouped => '未分组';

  @override
  String matchingScriptsCount(int visible, int total) {
    return '匹配 $visible / 共 $total 个';
  }

  @override
  String get projectMainProgramSet => '项目 · 已设置主程序';

  @override
  String get projectMainProgramNotSet => '项目 · 未设置主程序';

  @override
  String scriptsCount(int count) {
    return '$count 个脚本';
  }

  @override
  String runsCount(int count) {
    return '运行 $count 次';
  }

  @override
  String get notRun => '未运行';

  @override
  String scriptSemanticLabel(Object name) {
    return '脚本 $name';
  }

  @override
  String get openScript => '打开脚本';

  @override
  String get openAndRunScript => '打开脚本，可快速运行';

  @override
  String domainFilter(Object domain) {
    return '域名: $domain';
  }

  @override
  String methodFilter(Object method) {
    return '方法: $method';
  }

  @override
  String get statusFilterError => '状态: 错误';

  @override
  String statusFilter(Object status) {
    return '状态: $status';
  }

  @override
  String get filterNetworkRequests => '筛选网络请求';

  @override
  String get domainOrUrlKeyword => '域名 / URL 关键字';

  @override
  String get requestMethod => '请求方法';

  @override
  String get apply => '应用';

  @override
  String allRequestsCount(int count) {
    return '全部 $count';
  }

  @override
  String visibleRequestsCount(int visible, int total) {
    return '显示 $visible / 全部 $total';
  }

  @override
  String get clearNetworkRequests => '清空网络请求记录';

  @override
  String get clearNetworkRequestsConfirm => '确定要清空所有已捕获的网络请求记录吗？';

  @override
  String get openSettings => '去设置';

  @override
  String get linuxLikeNotInstalledAction => 'Linux-like 未安装，请先打开运行环境并完成安装';

  @override
  String get runtimeSwitchLinuxLike => 'Linux-like 已保存；执行和包管理将使用 Linux-like';

  @override
  String get runtimeSwitchChaquopy => '运行引擎已切换为 Chaquopy';

  @override
  String get selectRuntimeEngine => '选择运行引擎';

  @override
  String get chaquopyDescription => '基于 Python 官方实现，稳定可靠';

  @override
  String get linuxLikeDescription => 'Debian 环境，支持更多包';

  @override
  String get available => '可用';

  @override
  String get notInstalled => '未安装';

  @override
  String get pypiSourceSaved => 'PyPI 源已保存';

  @override
  String get officialSourceRestored => '已恢复官方源（https://pypi.org/simple）';

  @override
  String get downloadMirrorTitle => '下载加速镜像';

  @override
  String get downloadMirrorDescription => '填写 GitHub 代理前缀，加速 APK 下载';

  @override
  String get downloadMirrorEmptyHint => '留空则直接使用 GitHub 原始地址';

  @override
  String get selectScriptExportDirectory => '选择脚本导出目录';

  @override
  String get exportDirectorySet => '导出目录已设置';

  @override
  String get selectWorkingDirectory => '选择工作目录';

  @override
  String get workingDirectorySet => '工作目录已设置';

  @override
  String get securityWarning => '安全警告';

  @override
  String get insecureCertificateWarning =>
      '允许不安全证书将使网络连接不验证 SSL 证书，这会降低安全性。仅在使用抓包工具调试时启用。\n\n确定要启用吗？';

  @override
  String get proxyPortMustBeInteger => '代理端口必须是整数';

  @override
  String get proxyConfigurationSaved => '代理配置已保存';

  @override
  String fullLogsExportedTo(Object path) {
    return '完整日志已导出到: $path';
  }

  @override
  String get insecureCertificatesOn => '已开启 — 将信任自签名/抓包证书（降低安全性）';

  @override
  String get insecureCertificatesOff => '关闭 — 严格校验 SSL 证书';

  @override
  String get responsePreviewLimit => '文本前 10 MB，图片最大 30 MB（增加内存占用）';

  @override
  String get requestOverridesOn => '已开启 — 全局覆盖将应用到所有 Python HTTP 请求';

  @override
  String get requestOverridesOff => '关闭 — 不修改脚本的默认请求行为';

  @override
  String largeResponseCaptured(Object captured, Object total) {
    return '响应体较大，显示 $captured / $total。';
  }

  @override
  String get largeResponse => '响应体较大，当前仅显示已捕获的内容。';

  @override
  String get audio => '音频';

  @override
  String get video => '视频';

  @override
  String get media => '媒体';

  @override
  String get type => '类型';

  @override
  String get reset => '重置';

  @override
  String get fontSize => '字体大小';

  @override
  String get truncated => '已截断';

  @override
  String lineCount(int count) {
    return '$count 行';
  }

  @override
  String characterCount(int count) {
    return '$count 字符';
  }

  @override
  String capturedBytes(Object captured, Object total) {
    return '已捕获 $captured / $total';
  }

  @override
  String get treeView => '树形视图';

  @override
  String get exportJson => '导出 JSON';

  @override
  String get jsonTreeView => 'JSON 树形查看';

  @override
  String get searching => '搜索中';

  @override
  String get searchContent => '搜索内容...';

  @override
  String get imageDecodeFailed => '(图片解码失败)';

  @override
  String get imageRenderFailed => '(图片渲染失败)';

  @override
  String get size => '大小';

  @override
  String get systemLogs => '系统日志';

  @override
  String get logsCopiedCurrent => '已复制当前日志内容';

  @override
  String get searchLogsLabel => '搜索日志';

  @override
  String get searchLogsHint => '输入关键字过滤日志内容';

  @override
  String get section => '区块';

  @override
  String get noMatchingSystemLogs => '暂无匹配日志';

  @override
  String get about => '关于';

  @override
  String get localPythonRuntime => '本地 Python 脚本运行环境';

  @override
  String get pythonEnvironment => 'Python 环境';

  @override
  String get engine => '引擎';

  @override
  String get installDirectory => '安装目录';

  @override
  String get path => '路径';

  @override
  String get projectHomepage => '项目主页';

  @override
  String get groupName => '分组名称';

  @override
  String get projectName => '项目名称';

  @override
  String get scriptName => '脚本名称 (不含 .py)';

  @override
  String groupAdded(Object name) {
    return '已添加分组: $name';
  }

  @override
  String get groupCreateFailed => '分组创建失败或已存在';

  @override
  String get projectCreateFailed => '项目名称已存在或创建失败';

  @override
  String projectCreateError(Object error) {
    return '创建项目失败: $error';
  }

  @override
  String projectImportFailed(Object error) {
    return '导入项目失败: $error';
  }

  @override
  String get onlyPythonFiles => '只支持导入 .py 文件';

  @override
  String get scriptExists => '脚本已存在';

  @override
  String scriptExistsConfirm(Object name) {
    return '已存在同名脚本「$name」，是否覆盖？';
  }

  @override
  String get overwrite => '覆盖';

  @override
  String get exportToDevice => '导出到设备';

  @override
  String get moveToGroup => '移动到分组';

  @override
  String get moveToHome => '移出到首页';

  @override
  String get newGroup => '新建分组...';

  @override
  String selectedGroupsCount(int count) {
    return '已选 $count 个分组';
  }

  @override
  String selectedItemsCount(int count) {
    return '已选 $count 个';
  }

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get bulkDeleteGroups => '批量删除分组';

  @override
  String get bulkExport => '批量导出';

  @override
  String get bulkDelete => '批量删除';

  @override
  String get finishReordering => '结束排序';

  @override
  String get group => '分组';

  @override
  String get newScriptDescription => '创建一个空白 Python 脚本';

  @override
  String get importScriptDescription => '从设备选择 .py 文件';

  @override
  String scriptOverwritten(Object name) {
    return '已覆盖: $name';
  }

  @override
  String scriptImported(Object name) {
    return '已导入: $name';
  }

  @override
  String exportedScriptsTo(int count, Object path) {
    return '已导出 $count 个脚本到: $path';
  }

  @override
  String deleteScriptsConfirm(int count) {
    return '确定要删除选中的 $count 个脚本吗？此操作不可撤销。';
  }

  @override
  String deleteCount(int count) {
    return '删除 $count 个';
  }

  @override
  String scriptsDeleted(int count) {
    return '已删除 $count 个脚本';
  }

  @override
  String groupsDeleted(int count) {
    return '已删除 $count 个分组';
  }

  @override
  String get deleteScript => '删除脚本';

  @override
  String deleteScriptConfirm(Object name) {
    return '确定要删除 \"$name\" 吗？此操作不可撤销。';
  }

  @override
  String copyFailed(Object error) {
    return '复制失败: $error';
  }

  @override
  String groupsDeleteConfirm(int groups, int projects) {
    return '确定要删除选中的 $groups 个分组和 $projects 个项目吗？项目文件会一并删除，普通分组内脚本会回到首页。';
  }

  @override
  String groupsDeleteOnlyConfirm(int count) {
    return '确定要删除选中的 $count 个分组吗？分组内脚本会回到首页。';
  }

  @override
  String scriptsMovedHome(int count) {
    return '已将 $count 个脚本移出到首页';
  }

  @override
  String scriptsMovedTo(int count, Object group) {
    return '已将 $count 个脚本移动到「$group」';
  }

  @override
  String get projectFilesDeleted => '项目文件会一并删除';

  @override
  String get groupScriptsReturnHome => '分组内脚本会回到首页';

  @override
  String get deleteProject => '删除项目';

  @override
  String get deleteGroup => '删除分组';

  @override
  String deleteProjectConfirm(Object name) {
    return '确定要删除项目「$name」吗？项目文件会一并删除。';
  }

  @override
  String deleteGroupConfirm(Object name) {
    return '确定要删除「$name」吗？分组内脚本会回到首页。';
  }

  @override
  String get checksumUnavailable => '无法获取此版本的 SHA-256 完整性校验，自动安装已禁用。';

  @override
  String checksumUnavailableDetail(Object error) {
    return '原因：$error';
  }

  @override
  String networkRequestSemantics(
    Object method,
    Object domain,
    Object status,
    Object duration,
    Object time,
  ) {
    return '$method 请求，$domain，$status，耗时 $duration，时间 $time';
  }

  @override
  String get requestOverrideSettings => '请求覆盖配置';

  @override
  String get globalOverrides => '全局覆盖';

  @override
  String get globalUserAgent => 'User-Agent';

  @override
  String get globalHeaders => '全局请求头（JSON）';

  @override
  String get globalCookie => 'Cookie';

  @override
  String get defaultRequestTimeout => '默认请求超时（秒）';

  @override
  String get noDefaultTimeout => '0 表示不注入默认超时';

  @override
  String get followRedirects => '跟随重定向';

  @override
  String get useDebugProxyWhenUnset => '脚本未指定代理时使用调试代理';

  @override
  String get noValidDebugProxy => '请先在网络调试中配置有效代理';

  @override
  String get domainRules => '域名规则';

  @override
  String get domainRulesHint => '按顺序匹配，首条匹配规则覆盖同名全局字段。';

  @override
  String get addDomainRule => '添加域名规则';

  @override
  String get editDomainRule => '编辑域名规则';

  @override
  String get domainPattern => '域名或 *.example.com';

  @override
  String get ruleHeaders => '规则请求头（JSON，可选）';

  @override
  String get noDomainRules => '未配置域名规则';

  @override
  String get testDomain => '测试域名';

  @override
  String get previewEffectiveOverrides => '有效覆盖预览';

  @override
  String get noMatchingRule => '没有匹配的域名规则，将使用全局配置';

  @override
  String matchedRule(int index) {
    return '匹配规则 #$index';
  }

  @override
  String get saveOverrides => '保存覆盖配置';

  @override
  String get overridesSaved => '请求覆盖配置已保存，将在下次运行脚本时生效';

  @override
  String get copyOverrideConfig => '复制配置';

  @override
  String get pasteImportOverrides => '粘贴导入';

  @override
  String get importOverrideConfig => '导入请求覆盖配置';

  @override
  String get pasteOverrideConfigHint => '粘贴导出的 JSON 配置。导入失败不会修改当前配置。';

  @override
  String get overrideConfigCopied => '请求覆盖配置已复制';

  @override
  String get overrideConfigImported => '请求覆盖配置已导入';

  @override
  String get invalidOverrideConfig => '请求覆盖配置无效';

  @override
  String get sponsorProject => '赞助';

  @override
  String get sponsorProjectDescription => '使用微信扫一扫';

  @override
  String get sponsorQrHint => '感谢你的支持，请使用微信扫码赞助';

  @override
  String get appSubtitle => '本地 Python 脚本运行环境';

  @override
  String get pythonPath => 'Python 路径';

  @override
  String get technicalArchitecture => '技术架构';

  @override
  String get framework => '框架';

  @override
  String get nativeLayer => '原生层';

  @override
  String get storage => '存储';

  @override
  String get runtimeRequirements => '运行要求';

  @override
  String get architectureFrameworkValue =>
      'Flutter + Dart · Material 3 · Riverpod / Provider';

  @override
  String get architectureEngineValue =>
      'Chaquopy / Linux-like（Debian proot）可切换';

  @override
  String get architectureNativeValue =>
      'Kotlin · MethodChannel、EventChannel 与 Pigeon';

  @override
  String get architectureStorageValue => 'SharedPreferences + SQLite + 文件系统';

  @override
  String get architectureRequirementsValue => 'Android 8.0+ · arm64-v8a';

  @override
  String get mcpSectionTitle => 'AI / MCP 服务';

  @override
  String get mcpSectionDescription => '让外部 AI 客户端在授权后访问脚本、项目与库管理能力';

  @override
  String get mcpPageTitle => 'AI / MCP 服务';

  @override
  String get mcpService => 'MCP 服务';

  @override
  String get mcpStatusStopped => '已停止';

  @override
  String get mcpStatusStarting => '启动中…';

  @override
  String get mcpStatusRunning => '运行中';

  @override
  String get mcpStatusError => '错误';

  @override
  String mcpStartFailed(Object error) {
    return '启动失败：$error';
  }

  @override
  String get mcpOverlayPermissionRequired => '保活通知已启动；悬浮窗需要系统授权';

  @override
  String mcpKeepAliveUnavailable(Object error) {
    return 'MCP 已启动，保活不可用：$error';
  }

  @override
  String mcpHideOverlayFailed(Object error) {
    return '隐藏悬浮球失败：$error';
  }

  @override
  String get mcpLanUrl => '局域网 URL';

  @override
  String get mcpShowKeepAliveOverlay => '显示保活悬浮球';

  @override
  String get mcpHideOverlay => '隐藏悬浮球';

  @override
  String get mcpConnectionTokenHint =>
      '同一局域网设备可使用局域网 URL 连接。请求需携带 Authorization: Bearer <令牌>。';

  @override
  String get mcpConnectionNoTokenHint =>
      '同一局域网设备可使用局域网 URL 连接。当前未启用令牌认证，局域网内可访问此端口的设备都能调用。';

  @override
  String get mcpPortRange => '端口（1024-65535）';

  @override
  String get mcpRequirePairingToken => '启用密钥认证';

  @override
  String get mcpTokenDisabledWarning => '关闭后局域网请求无需密钥，请确认网络可信';

  @override
  String get mcpPairingToken => '配对密钥';

  @override
  String mcpCurrentToken(Object hint) {
    return '当前密钥：$hint';
  }

  @override
  String get mcpTokenGenerated => '已生成';

  @override
  String get mcpNoTokenYet => '尚未生成密钥';

  @override
  String get mcpRegenerate => '重新生成';

  @override
  String get mcpRegenerateTokenHint => '密钥可随时查看和复制。更新后，旧密钥立即失效，已连接客户端需更新配置。';

  @override
  String get mcpCustomToken => '自定义密钥';

  @override
  String get mcpCustomTokenValidation =>
      '使用 16–256 个英文字母、数字或 . _ ~ + / -，末尾可带 =。';

  @override
  String get mcpTokenSaved => '密钥已保存';

  @override
  String get mcpTokenSaveFailed => '密钥保存失败，原密钥未更改，请重试';

  @override
  String get mcpTokenStorageError => '无法读取密钥存储，请重试';

  @override
  String get mcpLegacyTokenHint =>
      '旧版本仅保存了摘要，无法还原完整密钥。可在自定义密钥中输入原密钥恢复显示，或重新生成。';

  @override
  String get mcpToolPermissions => '工具权限';

  @override
  String get mcpToolPermissionsHint => '已授权的操作直接执行，无逐次确认。运行和删除权限请按需开启。';

  @override
  String get mcpPermissionReadScripts => '读取脚本';

  @override
  String get mcpPermissionWriteScripts => '创建/修改脚本';

  @override
  String get mcpPermissionReadProjects => '读取项目';

  @override
  String get mcpPermissionWriteProjects => '创建项目/修改项目文件';

  @override
  String get mcpPermissionReadNetwork => '查询网络记录';

  @override
  String get mcpPermissionReadPackages => '查询已安装库';

  @override
  String get mcpPermissionInstallPackages => '安装库';

  @override
  String get mcpPermissionRunScripts => '运行脚本/交互输入/读取输出/停止运行';

  @override
  String get mcpPermissionWriteFilesystem => '新建目录/重命名/保存文件';

  @override
  String get mcpPermissionDeleteFilesystem => '删除文件/空目录';

  @override
  String get mcpPermissionReadFilesystem => '读取可访问文件';

  @override
  String get mcpCurrentConnections => '当前连接';

  @override
  String mcpSessionsCount(int count) {
    return '$count 个会话';
  }

  @override
  String get mcpNoConnections => '暂无连接。外部 AI 客户端完成 initialize 后会出现在这里。';

  @override
  String mcpSessionSummary(Object id, Object version) {
    return '会话 $id… · 协议 $version';
  }

  @override
  String get mcpDisconnect => '断开';

  @override
  String get mcpAuditLog => '审计日志';

  @override
  String mcpRecentToolCalls(int count) {
    return '最近 $count 次工具调用';
  }

  @override
  String get mcpClearAuditLog => '清空审计日志';

  @override
  String get mcpNoAuditRecords => '暂无记录。每次连接和工具调用都会写入审计日志（不含令牌与敏感内容）。';

  @override
  String mcpAuditToolCall(Object client, Object tool, int duration) {
    return '$client 调用 $tool（${duration}ms）';
  }

  @override
  String mcpAuditToolCallFailed(Object client, Object tool, Object error) {
    return '$client 调用 $tool 失败：$error';
  }

  @override
  String mcpAuditConnect(Object client) {
    return '$client 建立连接';
  }

  @override
  String mcpAuditDisconnect(Object client) {
    return '$client 断开连接';
  }

  @override
  String mcpAuditServer(Object status, Object details) {
    return 'MCP 服务 $status $details';
  }

  @override
  String get mcpPortSavedNextStart => '端口已保存，下次启动生效';

  @override
  String get mcpInvalidPort => '端口无效（需 1024-65535）';

  @override
  String get mcpRegenerateTokenTitle => '重新生成配对密钥';

  @override
  String get mcpRegenerateTokenConfirm =>
      '更换后旧密钥将立即失效，已连接的外部 AI 客户端需要更新密钥。继续吗？';

  @override
  String get mcpGenerate => '生成';

  @override
  String get mcpNewTokenTitle => '新密钥';

  @override
  String get mcpCopyToken => '复制密钥';

  @override
  String get mcpCopiedToClipboard => '已复制到剪贴板';

  @override
  String get mcpConfirmationTitle => 'AI 请求执行操作';

  @override
  String mcpConfirmationClient(Object client) {
    return '发起方：$client';
  }

  @override
  String mcpConfirmationAutoDeny(int seconds) {
    return '$seconds 秒内未处理将自动拒绝';
  }

  @override
  String get mcpConfirmationAutoDenySoon => '即将自动拒绝…';

  @override
  String get mcpDeny => '拒绝';

  @override
  String get mcpAllowSession => '本次会话允许';

  @override
  String get mcpAllow => '允许';

  @override
  String get backupTitle => '备份与恢复';

  @override
  String get backupDescription => '保存脚本和完整项目，或从备份恢复。';

  @override
  String get backupContents => '备份内容';

  @override
  String get backupChooseContents => '选择内容';

  @override
  String backupScope(int scripts, int projects, int groups) {
    return '$scripts 个脚本 · $projects 个项目 · $groups 个分组';
  }

  @override
  String get backupScopeHint => '包含项目文件及空分组，不包含设置和密码。';

  @override
  String get backupEmptyLibrary => '脚本库为空。可从备份恢复脚本或项目。';

  @override
  String get backupNothingSelected => '请至少选择一个脚本、项目或空分组。';

  @override
  String get backupExportLocal => '导出到本机';

  @override
  String get backupUpload => '备份到 WebDAV';

  @override
  String get backupRestoreLocal => '从本机恢复';

  @override
  String get backupRestoreRemote => '从 WebDAV 恢复';

  @override
  String get backupDestinations => '保存位置';

  @override
  String get backupLocalFolder => '本机文件夹';

  @override
  String get backupFolderUnset => '首次导出时选择文件夹。';

  @override
  String get backupChange => '更改';

  @override
  String get backupConfigure => '配置';

  @override
  String get backupCloudUnset => '配置安全的 WebDAV 服务器以使用云端备份。';

  @override
  String get backupActions => '备份';

  @override
  String get backupRestoreSection => '恢复';

  @override
  String get backupRestoreHint => '先检查内容和冲突，再确认恢复。';

  @override
  String get backupSelectAll => '全选';

  @override
  String get backupClearAll => '清空选择';

  @override
  String get backupUseSelection => '确认选择';

  @override
  String get backupEmptyGroup => '空分组';

  @override
  String get backupWholeProject => '完整项目，包含所有文件';

  @override
  String get backupRootScripts => '未分组脚本';

  @override
  String get backupWebDavTitle => 'WebDAV 连接';

  @override
  String get backupServerUrl => 'HTTPS 服务器地址';

  @override
  String get backupServerHint => 'https://cloud.example.com/dav/';

  @override
  String get backupUsername => '用户名';

  @override
  String get backupPassword => '密码或应用密码';

  @override
  String get backupKeepPassword => '留空以保留已保存的密码。';

  @override
  String get backupPasswordPrivate => '安全保存在本机。';

  @override
  String get backupShowPassword => '显示密码';

  @override
  String get backupHidePassword => '隐藏密码';

  @override
  String get backupRemoteDirectory => '远端目录';

  @override
  String get backupTestConnection => '测试连接';

  @override
  String get backupInvalidUrl => '请输入 HTTPS 地址，不要在地址中包含用户名、密码、查询或片段。';

  @override
  String get backupInvalidUsername => '请输入用户名，不可包含冒号或控制字符。';

  @override
  String get backupPasswordRequired => '请输入密码或应用密码。';

  @override
  String get backupInvalidDirectory => '用 / 分隔文件夹名；不可使用空名称、. 或 ..。';

  @override
  String get backupHistoryTitle => 'WebDAV 备份';

  @override
  String get backupHistoryEmpty => '此文件夹中暂无已完成的备份。';

  @override
  String get backupRefresh => '刷新';

  @override
  String get backupUnknownDate => '日期未知';

  @override
  String get backupUnknownSize => '大小未知';

  @override
  String get backupPreviewTitle => '检查恢复内容';

  @override
  String backupCreated(String date) {
    return '创建于 $date';
  }

  @override
  String get backupPolicyTitle => '名称冲突时';

  @override
  String get backupKeepBoth => '保留两者';

  @override
  String get backupKeepBothHint => '为恢复的内容使用新名称。';

  @override
  String get backupOverwrite => '覆盖现有内容';

  @override
  String get backupOverwriteHint => '替换同名脚本和整个项目。';

  @override
  String get backupSkip => '跳过现有内容';

  @override
  String get backupSkipHint => '保留现有内容，跳过与其同名的备份内容。';

  @override
  String get backupPlanTitle => '待确认的更改';

  @override
  String backupPlanCounts(
    int scripts,
    int projects,
    int replacements,
    int skipped,
  ) {
    return '将恢复 $scripts 个脚本和 $projects 个项目；替换 $replacements 个完整项目，跳过 $skipped 项。';
  }

  @override
  String backupRename(String from, String to) {
    return '$from → $to';
  }

  @override
  String backupReplaceItem(String name) {
    return '替换：$name';
  }

  @override
  String backupSkipItem(String name) {
    return '跳过：$name';
  }

  @override
  String get backupNoChanges => '当前选择与冲突处理方式下没有可恢复的内容。';

  @override
  String get backupPreviewUpdated => '脚本库已发生变化。请检查更新后的预览并再次确认。';

  @override
  String get backupRestoreNow => '恢复';

  @override
  String get backupConfirmTitle => '恢复所选内容？';

  @override
  String get backupConfirmBody => '所选内容将恢复到脚本库，其他内容将保留。';

  @override
  String get backupReplaceConfirm =>
      '同名脚本将被替换。同名项目的整个当前目录将被替换，包括备份中没有的文件。其他内容将保留。';

  @override
  String get backupDiscardPreview => '放弃此次恢复';

  @override
  String get backupLegacyTitle => '导入项目 ZIP';

  @override
  String get backupLegacyHint => '此 ZIP 为普通项目压缩包，不包含原脚本库信息，将作为新项目导入。';

  @override
  String get backupProjectName => '项目名称';

  @override
  String get backupInvalidProjectName => '请输入有效的项目名称。';

  @override
  String get backupEntryPoint => 'Python 入口文件';

  @override
  String get backupNoEntryPoint => '稍后选择';

  @override
  String get backupNoPythonFiles => '未找到 Python 文件。可以先导入项目，运行前再设置入口文件。';

  @override
  String get backupProgressPreparing => '正在准备…';

  @override
  String get backupProgressSelecting => '等待选择文件或文件夹…';

  @override
  String get backupProgressScanning => '正在检查文件…';

  @override
  String get backupProgressCompressing => '正在创建备份…';

  @override
  String get backupProgressCopying => '正在保存到本机…';

  @override
  String get backupProgressUploading => '正在上传备份…';

  @override
  String get backupProgressDownloading => '正在下载备份…';

  @override
  String get backupProgressValidating => '正在检查备份…';

  @override
  String get backupProgressStaging => '正在准备恢复…';

  @override
  String get backupProgressCommitting => '正在恢复文件，请保持应用打开。';

  @override
  String get backupProgressFinalizing => '正在完成恢复…';

  @override
  String backupSavedTo(String destination) {
    return '已保存：$destination';
  }

  @override
  String backupRestored(int scripts, int projects, int groups) {
    return '已恢复 $scripts 个脚本、$projects 个项目和 $groups 个分组。';
  }

  @override
  String get backupRestoreComplete => '恢复完成，脚本库已刷新。';

  @override
  String get backupConnectionVerified => '连接测试成功。';

  @override
  String get backupProfileSaved => '连接配置已保存。';

  @override
  String get backupCancelled => '操作已取消。';

  @override
  String get backupRetry => '重试';

  @override
  String get backupRetryRecovery => '重试恢复';

  @override
  String get backupRecoveryRequired => '恢复尚未完成，文件和恢复数据已保留。请检查可用存储空间后重试。';

  @override
  String get backupErrorAuthentication => '登录失败，请在 WebDAV 配置中检查用户名和密码。';

  @override
  String get backupErrorPermission => '无法访问，请检查文件夹权限或选择其他位置。';

  @override
  String get backupErrorLocalPermission => '已失去所选文件夹的访问权限，请重新选择文件夹后再次导出。';

  @override
  String get backupErrorInvalid => '此备份已损坏、存在不安全内容或格式不受支持，请选择其他 ZIP。';

  @override
  String get backupErrorVersion => '暂不支持此备份版本，请更新应用后重试。';

  @override
  String get backupErrorBusy => '另一个操作正在进行，请等待完成或关闭当前恢复预览。';

  @override
  String get backupErrorRunning => '请先停止正在运行的脚本，再备份或恢复。';

  @override
  String get backupErrorNetwork => '无法连接服务器，请检查网络和服务器地址后重试。';

  @override
  String get backupErrorStorage => '可用存储空间不足，请释放空间后重试。';

  @override
  String get backupErrorLimit => '此压缩包超出支持的文件数量、大小或信息限制，请使用较小的备份。';

  @override
  String get backupErrorConfiguration => '无法安全读取或保存连接配置，请重试或重新填写连接信息。';

  @override
  String get backupErrorSourceMissing =>
      '待备份的脚本或项目文件已不存在。请刷新备份内容，或取消选择缺失的项目后重试。';

  @override
  String get backupErrorSourceChanged => '文件在备份过程中发生变化。请停止编辑或修改文件后重试。';

  @override
  String get backupErrorGeneric => '操作未能完成，请检查存储空间与连接后重试。';
}
