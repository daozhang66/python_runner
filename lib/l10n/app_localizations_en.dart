// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Python Runner';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get chinese => 'Chinese';

  @override
  String get english => 'English';

  @override
  String get scriptDetails => 'Script details';

  @override
  String get selectScript => 'Select a script';

  @override
  String get selectScriptDescription =>
      'Select a script from the list to view details and quick actions.';

  @override
  String get edit => 'Edit';

  @override
  String get run => 'Run';

  @override
  String get openConsole => 'Open console';

  @override
  String get scriptGroup => 'Group';

  @override
  String get createdAt => 'Created';

  @override
  String get lastModified => 'Last modified';

  @override
  String get runCount => 'Run count';

  @override
  String get scriptStatus => 'Status';

  @override
  String get running => 'Running';

  @override
  String get idle => 'Idle';

  @override
  String get pinned => 'Pinned';

  @override
  String get regularScript => 'Regular script';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get loadingScripts => 'Loading scripts';

  @override
  String get loadingPackages => 'Loading installed packages';

  @override
  String get loadPackagesFailed => 'Unable to load packages';

  @override
  String get retry => 'Retry';

  @override
  String get enableAutoFollow => 'Enable auto-follow';

  @override
  String get disableAutoFollow => 'Disable auto-follow';

  @override
  String get exportLogs => 'Export logs';

  @override
  String get scripts => 'Scripts';

  @override
  String get network => 'Network';

  @override
  String get packageManager => 'Packages';

  @override
  String get networkRequests => 'Network requests';

  @override
  String get searchUrlOrDomain => 'Search URL / domain...';

  @override
  String get showNoiseRequests => 'Show DNS/connect/process records';

  @override
  String get hideNoiseRequests => 'Hide DNS/connect/process records';

  @override
  String get filter => 'Filter';

  @override
  String get clear => 'Clear';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get noNetworkRequests => 'No network requests';

  @override
  String get noMatchingRequests => 'No matching requests';

  @override
  String get runNetworkScriptHint =>
      'Run a script that makes network requests to see them here';

  @override
  String get tryClearingFilters => 'Try clearing the filters';

  @override
  String get update => 'Update';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get imagePreview => 'Image preview';

  @override
  String get search => 'Search';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get updateNow => 'Update now';

  @override
  String get dontRemind => 'Don\'t remind me';

  @override
  String get releaseNotes => 'Release notes';

  @override
  String fileSize(Object size) {
    return 'Size: $size';
  }

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String todayAt(Object time) {
    return 'Today $time';
  }

  @override
  String yesterdayAt(Object time) {
    return 'Yesterday $time';
  }

  @override
  String get unknownReleaseDate => 'Release date unknown';

  @override
  String get updateLog => 'Update log';

  @override
  String get searchVersionOrNotes => 'Search versions or release notes';

  @override
  String get updateLogLoadFailed => 'Unable to load update logs';

  @override
  String openReleaseFailed(Object error) {
    return 'Unable to open release page: $error';
  }

  @override
  String get noReleaseLogs => 'No update logs';

  @override
  String get noMatchingReleaseLogs => 'No matching update logs';

  @override
  String get unnamedRelease => 'Unnamed release';

  @override
  String get prerelease => 'Pre-release';

  @override
  String get noReleaseNotes => 'This release has no notes.';

  @override
  String get releasePage => 'Release page';

  @override
  String get appLogs => 'App logs';

  @override
  String get refresh => 'Refresh';

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get searchLogContent => 'Search log content';

  @override
  String get noLogs => 'No logs';

  @override
  String get noMatchingLogs => 'No matching logs';

  @override
  String get logsCopied => 'Logs copied to clipboard';

  @override
  String get clearLogsConfirm => 'Clear all logs? This cannot be undone.';

  @override
  String get logsCleared => 'Logs cleared';

  @override
  String get level => 'Level';

  @override
  String get source => 'Source';

  @override
  String get time => 'Time';

  @override
  String get all => 'All';

  @override
  String get lastSevenDays => 'Last 7 days';

  @override
  String get total => 'Total';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count hr ago';
  }

  @override
  String get install => 'Install';

  @override
  String get uninstall => 'Uninstall';

  @override
  String get repair => 'Repair';

  @override
  String get copyInstallLog => 'Copy installation log';

  @override
  String get installLogCopied => 'Installation log copied';

  @override
  String get searchInstalledPackages => 'Search installed packages...';

  @override
  String get packageName => 'Package name';

  @override
  String get version => 'Version';

  @override
  String get noPackages => 'No packages';

  @override
  String get noMatchingPackages => 'No matching packages';

  @override
  String get unknownVersion => 'Unknown version';

  @override
  String userInstalledPackages(int count) {
    return 'User installed ($count)';
  }

  @override
  String builtInPackages(int count) {
    return 'Built-in ($count)';
  }

  @override
  String get uninstallPackage => 'Uninstall package';

  @override
  String uninstallPackageConfirm(Object name) {
    return 'Uninstall \"$name\"?';
  }

  @override
  String get pythonRunnerSlogan => 'Life is short, use Python';

  @override
  String get terminalTheme => 'Terminal theme';

  @override
  String get darkTerminal => 'Dark terminal';

  @override
  String get lightTerminal => 'Light terminal';

  @override
  String get followSystem => 'Follow system';

  @override
  String get monochromeOutput => 'Monochrome output';

  @override
  String get showLineNumbers => 'Show line numbers';

  @override
  String get hideLineNumbers => 'Hide line numbers';

  @override
  String get showAll => 'Show all';

  @override
  String get copyAll => 'Copy all';

  @override
  String get searchLogs => 'Search logs...';

  @override
  String get onlyErrors => 'Errors only';

  @override
  String get closeSearch => 'Close search';

  @override
  String get noMatchingOutput => 'No matching output';

  @override
  String get waitingForOutput => 'Waiting for output...';

  @override
  String get noOutput => 'No output';

  @override
  String get newOutputAvailable => 'New output. Tap to jump to the bottom.';

  @override
  String get inputContent => 'Enter input...';

  @override
  String get waitingForInput => 'Waiting for script input...';

  @override
  String get stop => 'Stop';

  @override
  String get runAgain => 'Run again';

  @override
  String get waitingForInputStatus => 'Waiting for input';

  @override
  String get error => 'Error';

  @override
  String get timeout => 'Timed out';

  @override
  String get stopped => 'Stopped';

  @override
  String get finished => 'Finished';

  @override
  String get noRun => 'No active run';

  @override
  String get logsExported => 'Logs exported';

  @override
  String logsExportedTo(Object path) {
    return 'Logs exported to $path';
  }

  @override
  String copiedAllLines(int count) {
    return 'Copied all $count lines';
  }

  @override
  String get exportFailedTryAgain => 'Export failed. Try again later.';

  @override
  String get manageRuntime => 'Manage runtime';

  @override
  String get runtimeInstalled => 'Linux-like runtime is installed';

  @override
  String get runtimeNotInstalled => 'Linux-like runtime is not installed';

  @override
  String get installRuntime => 'Install runtime';

  @override
  String get repairRuntime => 'Repair runtime';

  @override
  String get runtimeInstalledSuccess => 'Linux-like runtime installed';

  @override
  String get runtimeAbout => 'About the Linux-like runtime';

  @override
  String get runtimeDescription =>
      'The Linux-like runtime is experimental and provides a complete Linux environment with broader Python package and tool support.\n\n• Debian base system\n• Python 3 and pip preinstalled\n• Native extension compilation\n• Better compatibility';

  @override
  String get preparing => 'Preparing...';

  @override
  String get processing => 'Processing...';

  @override
  String get runtimeDownloadRequirement =>
      'Downloads about 104 MB of Debian, Python, pip, and build-essential packages';

  @override
  String get allFiles => 'All files';

  @override
  String get back => 'Back';

  @override
  String get upOneLevel => 'Up one level';

  @override
  String get select => 'Select';

  @override
  String get internalStorage => 'Internal storage';

  @override
  String get systemFilePicker => 'System file picker';

  @override
  String get storageLocations => 'Storage locations';

  @override
  String searchFiles(Object filter) {
    return 'Search $filter';
  }

  @override
  String get noBrowsableFiles => 'No files to browse';

  @override
  String noFilesInDirectory(Object filter) {
    return 'No $filter in this directory';
  }

  @override
  String get systemFilePickerHint =>
      'Use the system file picker from the top-right corner.';

  @override
  String get goUpOrInternalStorageHint =>
      'Go up one level or return to internal storage.';

  @override
  String get runtimeEngine => 'Runtime engine';

  @override
  String get chaquopyDefault => 'Chaquopy (default)';

  @override
  String get linuxLikeExperimental => 'Linux-like (experimental)';

  @override
  String get pypiSource => 'PyPI source';

  @override
  String get useOfficialSourceWhenEmpty =>
      'Leave empty to use the official source';

  @override
  String get restoreOfficialSource => 'Restore official source';

  @override
  String get script => 'Script';

  @override
  String get executionTimeout => 'Execution timeout';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get workingDirectory => 'Working directory';

  @override
  String get defaultWorkingDirectory =>
      'Default: /storage/emulated/0/Download/PythonRunner';

  @override
  String get scriptWorkingDirectoryDescription =>
      'Base directory for script file I/O';

  @override
  String get scriptExportDirectory => 'Script export directory';

  @override
  String get defaultDownloadDirectory => 'Default: Downloads';

  @override
  String get networkDebugMode => 'Network debug mode';

  @override
  String get networkDebugModeDescription =>
      'Configure proxy and certificate options when enabled';

  @override
  String get allowInsecureCertificates => 'Allow insecure certificates';

  @override
  String get proxyConfigurationOptional => 'Proxy configuration (optional)';

  @override
  String get proxyConfigurationDescription =>
      'Network requests will use this proxy';

  @override
  String get proxyAddress => 'Proxy address';

  @override
  String get port => 'Port';

  @override
  String get recordNetworkRequests => 'Record network requests';

  @override
  String get recordNetworkRequestsDescription =>
      'Capture HTTP, DNS, socket, and common network commands';

  @override
  String get recordResponsePreview => 'Record response previews';

  @override
  String get enableRequestOverrides => 'Enable request overrides';

  @override
  String get systemTools => 'System tools';

  @override
  String get exportFullLogs => 'Export full logs';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get autoCheckUpdates => 'Check for updates at startup';

  @override
  String get downloadMirror => 'Download mirror';

  @override
  String get aboutApp => 'About app';

  @override
  String get general => 'General';

  @override
  String get themeAndColors => 'Theme and colors';

  @override
  String get appLogsDescription =>
      'View and filter system logs, crash logs, and script errors';

  @override
  String get exportFullLogsDescription =>
      'Export full diagnostics to the working directory or its default';

  @override
  String get checkForUpdatesDescription =>
      'Get the latest APK from GitHub Releases';

  @override
  String get updateLogDescription => 'View GitHub Releases history';

  @override
  String get autoCheckUpdatesDescription =>
      'Check for updates whenever the app starts';

  @override
  String get mirrorNotConfigured => 'Not configured (tap to set)';

  @override
  String get themeAndColorsDescription =>
      'Theme mode, Material You, palettes, custom colors, and fonts';

  @override
  String hours(Object value) {
    return '$value hours';
  }

  @override
  String minutes(Object value) {
    return '$value minutes';
  }

  @override
  String seconds(Object value) {
    return '$value seconds';
  }

  @override
  String get requestOverrideWarning =>
      'This globally overrides User-Agent, headers, cookies, timeouts, and other HTTP settings in Python scripts.\n\nIt changes actual script behavior and should only be used for debugging.';

  @override
  String get confirmEnable => 'Enable';

  @override
  String get saved => 'Saved';

  @override
  String get save => 'Save';

  @override
  String get unsaved => 'Unsaved';

  @override
  String get synced => 'Synced';

  @override
  String get modified => 'Modified';

  @override
  String get readOnly => 'Read-only';

  @override
  String get editorActions => 'Editor actions';

  @override
  String get indent => 'Indent';

  @override
  String get outdent => 'Outdent';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get enterEditMode => 'Edit';

  @override
  String get switchToReadOnly => 'Switch to read-only';

  @override
  String get fullScreenTerminal => 'Full-screen terminal';

  @override
  String get openingScript => 'Opening script';

  @override
  String get more => 'More';

  @override
  String get runProject => 'Run project';

  @override
  String get newFile => 'New file';

  @override
  String get newDirectory => 'New directory';

  @override
  String get create => 'Create';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get fileCreated => 'Created';

  @override
  String get createFailed => 'Unable to create';

  @override
  String get renamed => 'Renamed';

  @override
  String get renameFailed => 'Unable to rename';

  @override
  String get deleted => 'Deleted';

  @override
  String get deleteFailed => 'Unable to delete';

  @override
  String get deleteFile => 'Delete file';

  @override
  String get deleteDirectory => 'Delete directory';

  @override
  String deletePathConfirm(Object path) {
    return 'Delete \"$path\"?';
  }

  @override
  String get installRequirements => 'Install requirements.txt';

  @override
  String get requirementsLinuxOnly =>
      'requirements.txt is only supported by Linux-like';

  @override
  String get selectRequirements => 'Select requirements.txt';

  @override
  String get emptyRequirements => 'requirements.txt is empty or cannot be read';

  @override
  String get emptyRequirementsShort => 'requirements.txt is empty';

  @override
  String userPackages(int count) {
    return 'User installed ($count)';
  }

  @override
  String get installing => 'Installing';

  @override
  String get copyLog => 'Copy log';

  @override
  String get packageMissing => 'Package files missing';

  @override
  String get damaged => 'Damaged';

  @override
  String get user => 'User';

  @override
  String get builtIn => 'Built-in';

  @override
  String get reinstallRepair => 'Reinstall and repair';

  @override
  String get addScript => 'Add script';

  @override
  String get addGroup => 'Add group';

  @override
  String get newProject => 'New project';

  @override
  String get importProjectZip => 'Import project ZIP';

  @override
  String get searchScripts => 'Search scripts';

  @override
  String get listView => 'List view';

  @override
  String get gridView => 'Grid view';

  @override
  String get reorderScripts => 'Reorder scripts';

  @override
  String get multiSelect => 'Multi-select';

  @override
  String get showScriptNames => 'Show script names';

  @override
  String get hideScriptNames => 'Hide script names';

  @override
  String get searchScriptsHint => 'Search scripts...';

  @override
  String get noMatches => 'No matches';

  @override
  String get noScripts => 'No scripts yet';

  @override
  String get createScriptFromMenu => 'Create a script from the top-right menu';

  @override
  String get tryOtherKeywords => 'Try other keywords';

  @override
  String get requestDetailsCopied => 'Request details copied';

  @override
  String get overview => 'Overview';

  @override
  String requestHeaders(int count) {
    return 'Request headers ($count)';
  }

  @override
  String get requestBody => 'Request body';

  @override
  String get response => 'Response';

  @override
  String responseHeaders(int count) {
    return 'Response headers ($count)';
  }

  @override
  String get responseImage => 'Response image';

  @override
  String get responseMedia => 'Response media';

  @override
  String get responsePreview => 'Response preview';

  @override
  String get responseBody => 'Response body';

  @override
  String get viewOriginalImage => 'View original image';

  @override
  String get viewFullContent => 'View full content';

  @override
  String get timeLabel => 'Time';

  @override
  String get method => 'Method';

  @override
  String get library => 'Library';

  @override
  String get duration => 'Duration';

  @override
  String get proxy => 'Proxy';

  @override
  String get sslVerification => 'SSL verification';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get statusCode => 'Status code';

  @override
  String get errorType => 'Error type';

  @override
  String get errorMessage => 'Error message';

  @override
  String get mainProgramUpdateFailed => 'Unable to update main program';

  @override
  String get mainProgramSet => 'Main program set';

  @override
  String get mainProgramNotSet => 'Main program not set';

  @override
  String get unableToReadZipPath => 'Unable to read ZIP path';

  @override
  String get importFailed => 'Import failed';

  @override
  String get zipImportComplete => 'ZIP import complete';

  @override
  String get exportFailed => 'Export failed';

  @override
  String exportedTo(Object path) {
    return 'Exported to: $path';
  }

  @override
  String get linuxLikeOnly => 'Linux-like only';

  @override
  String get installTaskInProgress => 'Installation in progress';

  @override
  String get projectRequirementsLinuxOnly =>
      'requirements.txt is only supported by Linux-like';

  @override
  String get installAlreadyInProgress =>
      'An installation is already running. Try again later.';

  @override
  String get loading => 'Loading';

  @override
  String get projectLaunchFailed => 'Unable to start project';

  @override
  String get exportProjectZip => 'Export project ZIP';

  @override
  String get setMainProgram => 'Set main program';

  @override
  String get installDependencies => 'Install dependencies';

  @override
  String get waitingForInstallLog => 'Waiting for installation log...';

  @override
  String get installationComplete => 'Installation complete';

  @override
  String get installationCompleteRefreshingPackages =>
      'Installation complete. Refreshing package list...';

  @override
  String get close => 'Close';

  @override
  String get projectRootDirectory => 'Project root';

  @override
  String itemsCount(int count) {
    return '$count items';
  }

  @override
  String get noFilesInProject => 'No files in this project';

  @override
  String get currentDirectoryEmpty => 'This directory is empty';

  @override
  String get mainProgram => 'Main program';

  @override
  String invalidPath(Object error) {
    return 'Invalid path: $error';
  }

  @override
  String get selectMainProgram => 'Select main program';

  @override
  String get searchPythonFiles => 'Search .py files';

  @override
  String get noPythonFilesFound => 'No .py files found';

  @override
  String get recommended => 'Recommended';

  @override
  String get enterMainProgramPath => 'Enter manually: package/main.py';

  @override
  String get doNotSet => 'Do not set';

  @override
  String get installSuccess => 'Success';

  @override
  String installFailed(Object error) {
    return 'Installation failed: $error';
  }

  @override
  String packageUninstallFailed(Object name) {
    return 'Unable to uninstall $name';
  }

  @override
  String packageUninstalled(Object name) {
    return '$name uninstalled';
  }

  @override
  String packageUninstalledDependencies(Object name, Object dependencies) {
    return '$name uninstalled and removed $dependencies';
  }

  @override
  String get repairPackage => 'Repair package';

  @override
  String repairPackageConfirm(Object name) {
    return 'Reinstall \"$name\"? A network connection may be required.';
  }

  @override
  String get installPythonPackage => 'Install Python packages above';

  @override
  String get noBuiltinPackagesReturned =>
      'The current runtime returned no built-in packages';

  @override
  String get themeMode => 'Theme mode';

  @override
  String get selectThemeMode => 'Select theme mode';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get materialYouWallpaper => 'Use wallpaper dynamic colors';

  @override
  String get materialYouOn =>
      'Android 12+ · Enabled. Colors follow the wallpaper.';

  @override
  String get materialYouOff =>
      'Android 12+ · Disable to use custom colors below.';

  @override
  String get presetThemes => 'Preset themes';

  @override
  String get moreColors => 'More colors';

  @override
  String get deleteColor => 'Delete color';

  @override
  String get deleteColorConfirm => 'Delete this custom color?';

  @override
  String get color => 'Color';

  @override
  String get blue => 'Blue';

  @override
  String get purple => 'Purple';

  @override
  String get green => 'Green';

  @override
  String get orange => 'Orange';

  @override
  String get pink => 'Pink';

  @override
  String get teal => 'Teal';

  @override
  String get red => 'Red';

  @override
  String get indigo => 'Indigo';

  @override
  String get amber => 'Amber';

  @override
  String get advancedOptions => 'Advanced options';

  @override
  String get colorSchemeAlgorithm => 'Color scheme algorithm';

  @override
  String get blurEffect => 'Blur effect';

  @override
  String get blurEffectDescription =>
      'Blur dialog backgrounds when supported by the color scheme algorithm';

  @override
  String get font => 'Font';

  @override
  String get selectColorSchemeAlgorithm => 'Select color scheme algorithm';

  @override
  String get selectFont => 'Select font';

  @override
  String get hue => 'Hue';

  @override
  String get saturation => 'Saturation';

  @override
  String get lightness => 'Lightness';

  @override
  String get variantTonalSpot => 'Tonal spot (recommended)';

  @override
  String get variantFidelity => 'Fidelity';

  @override
  String get variantContent => 'Content';

  @override
  String get variantMonochrome => 'Monochrome';

  @override
  String get variantNeutral => 'Neutral';

  @override
  String get variantVibrant => 'Vibrant';

  @override
  String get variantExpressive => 'Expressive';

  @override
  String get variantRainbow => 'Rainbow';

  @override
  String get variantFruitSalad => 'Fruit salad';

  @override
  String get variantTonalSpotDescription =>
      'Balanced soft colors for most scenarios';

  @override
  String get variantFidelityDescription => 'Most faithful to the seed color';

  @override
  String get variantContentDescription => 'Prioritizes content readability';

  @override
  String get variantMonochromeDescription => 'Minimal monochrome colors';

  @override
  String get variantNeutralDescription => 'Neutral, low-saturation colors';

  @override
  String get variantVibrantDescription => 'Vivid, high-saturation colors';

  @override
  String get variantExpressiveDescription => 'Bold, expressive colors';

  @override
  String get variantRainbowDescription => 'Multicolored like a rainbow';

  @override
  String get variantFruitSaladDescription => 'A rich fruit-salad palette';

  @override
  String get add => 'Add';

  @override
  String get selectColor => 'Select color';

  @override
  String get themeOcean => 'Ocean';

  @override
  String get themeMint => 'Mint';

  @override
  String get themeLilac => 'Lilac';

  @override
  String get themeHighContrast => 'High contrast';

  @override
  String runFailed(Object error) {
    return 'Run failed: $error';
  }

  @override
  String get modifiedAtUnknown => 'Modification time unknown';

  @override
  String modifiedAt(Object time) {
    return 'Modified $time';
  }

  @override
  String get readOnlyMode => 'Read-only';

  @override
  String get editingMode => 'Edit';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get ungrouped => 'Ungrouped';

  @override
  String matchingScriptsCount(int visible, int total) {
    return '$visible of $total matches';
  }

  @override
  String get projectMainProgramSet => 'Project · main program set';

  @override
  String get projectMainProgramNotSet => 'Project · main program not set';

  @override
  String scriptsCount(int count) {
    return '$count scripts';
  }

  @override
  String runsCount(int count) {
    return 'Run $count times';
  }

  @override
  String get notRun => 'Not run';

  @override
  String scriptSemanticLabel(Object name) {
    return 'Script $name';
  }

  @override
  String get openScript => 'Open script';

  @override
  String get openAndRunScript => 'Open script and run quickly';

  @override
  String domainFilter(Object domain) {
    return 'Domain: $domain';
  }

  @override
  String methodFilter(Object method) {
    return 'Method: $method';
  }

  @override
  String get statusFilterError => 'Status: error';

  @override
  String statusFilter(Object status) {
    return 'Status: $status';
  }

  @override
  String get filterNetworkRequests => 'Filter network requests';

  @override
  String get domainOrUrlKeyword => 'Domain / URL keyword';

  @override
  String get requestMethod => 'Request method';

  @override
  String get apply => 'Apply';

  @override
  String allRequestsCount(int count) {
    return 'All $count';
  }

  @override
  String visibleRequestsCount(int visible, int total) {
    return 'Showing $visible of $total';
  }

  @override
  String get clearNetworkRequests => 'Clear network request records';

  @override
  String get clearNetworkRequestsConfirm =>
      'Clear all captured network request records?';

  @override
  String get openSettings => 'Open settings';

  @override
  String get linuxLikeNotInstalledAction =>
      'Linux-like is not installed. Open the runtime settings and install it first.';

  @override
  String get runtimeSwitchLinuxLike =>
      'Linux-like saved. Execution and package management will use Linux-like.';

  @override
  String get runtimeSwitchChaquopy => 'Runtime switched to Chaquopy';

  @override
  String get selectRuntimeEngine => 'Select runtime engine';

  @override
  String get chaquopyDescription =>
      'Stable runtime based on the official Python implementation';

  @override
  String get linuxLikeDescription =>
      'Debian environment with support for more packages';

  @override
  String get available => 'Available';

  @override
  String get notInstalled => 'Not installed';

  @override
  String get pypiSourceSaved => 'PyPI source saved';

  @override
  String get officialSourceRestored =>
      'Official source restored (https://pypi.org/simple)';

  @override
  String get downloadMirrorTitle => 'Download acceleration mirror';

  @override
  String get downloadMirrorDescription =>
      'Enter a GitHub proxy prefix to accelerate APK downloads';

  @override
  String get downloadMirrorEmptyHint =>
      'Leave empty to use the original GitHub URL';

  @override
  String get selectScriptExportDirectory => 'Select script export directory';

  @override
  String get exportDirectorySet => 'Export directory set';

  @override
  String get selectWorkingDirectory => 'Select working directory';

  @override
  String get workingDirectorySet => 'Working directory set';

  @override
  String get securityWarning => 'Security warning';

  @override
  String get insecureCertificateWarning =>
      'Allowing insecure certificates disables SSL verification and reduces security. Enable this only when debugging with a traffic capture tool.\n\nEnable it?';

  @override
  String get proxyPortMustBeInteger => 'Proxy port must be an integer';

  @override
  String get proxyConfigurationSaved => 'Proxy configuration saved';

  @override
  String fullLogsExportedTo(Object path) {
    return 'Full logs exported to: $path';
  }

  @override
  String get insecureCertificatesOn =>
      'On — self-signed and capture certificates are trusted (less secure)';

  @override
  String get insecureCertificatesOff =>
      'Off — SSL certificates are strictly verified';

  @override
  String get responsePreviewLimit =>
      'First 10 MB of text; images up to 30 MB (uses more memory)';

  @override
  String get requestOverridesOn =>
      'On — global overrides apply to all Python HTTP requests';

  @override
  String get requestOverridesOff =>
      'Off — script default request behavior is unchanged';

  @override
  String largeResponseCaptured(Object captured, Object total) {
    return 'Response body is large. Showing $captured / $total.';
  }

  @override
  String get largeResponse =>
      'Response body is large. Showing captured content only.';

  @override
  String get audio => 'Audio';

  @override
  String get video => 'Video';

  @override
  String get media => 'Media';

  @override
  String get type => 'Type';

  @override
  String get reset => 'Reset';

  @override
  String get fontSize => 'Font size';

  @override
  String get truncated => 'Truncated';

  @override
  String lineCount(int count) {
    return '$count lines';
  }

  @override
  String characterCount(int count) {
    return '$count characters';
  }

  @override
  String capturedBytes(Object captured, Object total) {
    return 'Captured $captured / $total';
  }

  @override
  String get treeView => 'Tree view';

  @override
  String get exportJson => 'Export JSON';

  @override
  String get jsonTreeView => 'JSON tree view';

  @override
  String get searching => 'Searching';

  @override
  String get searchContent => 'Search content...';

  @override
  String get imageDecodeFailed => '(Unable to decode image)';

  @override
  String get imageRenderFailed => '(Unable to render image)';

  @override
  String get size => 'Size';

  @override
  String get systemLogs => 'System logs';

  @override
  String get logsCopiedCurrent => 'Current logs copied';

  @override
  String get searchLogsLabel => 'Search logs';

  @override
  String get searchLogsHint => 'Enter a keyword to filter log content';

  @override
  String get section => 'Section';

  @override
  String get noMatchingSystemLogs => 'No matching logs';

  @override
  String get about => 'About';

  @override
  String get localPythonRuntime => 'Local Python script runtime';

  @override
  String get pythonEnvironment => 'Python environment';

  @override
  String get engine => 'Engine';

  @override
  String get installDirectory => 'Install directory';

  @override
  String get path => 'Path';

  @override
  String get projectHomepage => 'Project homepage';

  @override
  String get groupName => 'Group name';

  @override
  String get projectName => 'Project name';

  @override
  String get scriptName => 'Script name (without .py)';

  @override
  String groupAdded(Object name) {
    return 'Group added: $name';
  }

  @override
  String get groupCreateFailed =>
      'Unable to create group or group already exists';

  @override
  String get projectCreateFailed =>
      'Project name already exists or project creation failed';

  @override
  String projectCreateError(Object error) {
    return 'Unable to create project: $error';
  }

  @override
  String projectImportFailed(Object error) {
    return 'Unable to import project: $error';
  }

  @override
  String get onlyPythonFiles => 'Only .py files can be imported';

  @override
  String get scriptExists => 'Script already exists';

  @override
  String scriptExistsConfirm(Object name) {
    return 'A script named \"$name\" already exists. Overwrite it?';
  }

  @override
  String get overwrite => 'Overwrite';

  @override
  String get exportToDevice => 'Export to device';

  @override
  String get moveToGroup => 'Move to group';

  @override
  String get moveToHome => 'Move to home';

  @override
  String get newGroup => 'New group...';

  @override
  String selectedGroupsCount(int count) {
    return '$count groups selected';
  }

  @override
  String selectedItemsCount(int count) {
    return '$count selected';
  }

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get bulkDeleteGroups => 'Delete groups in bulk';

  @override
  String get bulkExport => 'Export in bulk';

  @override
  String get bulkDelete => 'Delete in bulk';

  @override
  String get finishReordering => 'Finish reordering';

  @override
  String get group => 'Group';

  @override
  String get newScriptDescription => 'Create a blank Python script';

  @override
  String get importScriptDescription => 'Select a .py file from the device';

  @override
  String scriptOverwritten(Object name) {
    return 'Overwritten: $name';
  }

  @override
  String scriptImported(Object name) {
    return 'Imported: $name';
  }

  @override
  String exportedScriptsTo(int count, Object path) {
    return 'Exported $count scripts to: $path';
  }

  @override
  String deleteScriptsConfirm(int count) {
    return 'Delete the selected $count scripts? This cannot be undone.';
  }

  @override
  String deleteCount(int count) {
    return 'Delete $count';
  }

  @override
  String scriptsDeleted(int count) {
    return 'Deleted $count scripts';
  }

  @override
  String groupsDeleted(int count) {
    return 'Deleted $count groups';
  }

  @override
  String get deleteScript => 'Delete script';

  @override
  String deleteScriptConfirm(Object name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String copyFailed(Object error) {
    return 'Copy failed: $error';
  }

  @override
  String groupsDeleteConfirm(int groups, int projects) {
    return 'Delete the selected $groups groups and $projects projects? Project files will also be deleted and scripts in regular groups return home.';
  }

  @override
  String groupsDeleteOnlyConfirm(int count) {
    return 'Delete the selected $count groups? Scripts in those groups return home.';
  }

  @override
  String scriptsMovedHome(int count) {
    return 'Moved $count scripts to home';
  }

  @override
  String scriptsMovedTo(int count, Object group) {
    return 'Moved $count scripts to \"$group\"';
  }

  @override
  String get projectFilesDeleted => 'Project files will also be deleted';

  @override
  String get groupScriptsReturnHome => 'Scripts in the group return home';

  @override
  String get deleteProject => 'Delete project';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String deleteProjectConfirm(Object name) {
    return 'Delete project \"$name\"? Its files will also be deleted.';
  }

  @override
  String deleteGroupConfirm(Object name) {
    return 'Delete \"$name\"? Scripts in the group return home.';
  }

  @override
  String get checksumUnavailable =>
      'The SHA-256 integrity check for this release could not be retrieved. Automatic installation is disabled.';

  @override
  String checksumUnavailableDetail(Object error) {
    return 'Reason: $error';
  }

  @override
  String networkRequestSemantics(Object method, Object domain, Object status,
      Object duration, Object time) {
    return '$method request, $domain, $status, duration $duration, time $time';
  }

  @override
  String get requestOverrideSettings => 'Request override settings';

  @override
  String get globalOverrides => 'Global overrides';

  @override
  String get globalUserAgent => 'User-Agent';

  @override
  String get globalHeaders => 'Global headers (JSON)';

  @override
  String get globalCookie => 'Cookie';

  @override
  String get defaultRequestTimeout => 'Default request timeout (seconds)';

  @override
  String get noDefaultTimeout => '0 does not inject a default timeout';

  @override
  String get followRedirects => 'Follow redirects';

  @override
  String get useDebugProxyWhenUnset =>
      'Use the debug proxy when the script has none';

  @override
  String get noValidDebugProxy =>
      'Configure a valid proxy in Network debug first';

  @override
  String get domainRules => 'Domain rules';

  @override
  String get domainRulesHint =>
      'Rules are matched in order. The first match overrides global fields with the same name.';

  @override
  String get addDomainRule => 'Add domain rule';

  @override
  String get editDomainRule => 'Edit domain rule';

  @override
  String get domainPattern => 'Domain or *.example.com';

  @override
  String get ruleHeaders => 'Rule headers (JSON, optional)';

  @override
  String get noDomainRules => 'No domain rules configured';

  @override
  String get testDomain => 'Test domain';

  @override
  String get previewEffectiveOverrides => 'Effective override preview';

  @override
  String get noMatchingRule =>
      'No domain rule matches; global settings are used';

  @override
  String matchedRule(int index) {
    return 'Matched rule #$index';
  }

  @override
  String get saveOverrides => 'Save override settings';

  @override
  String get overridesSaved =>
      'Request overrides saved. They apply when the next script starts.';

  @override
  String get copyOverrideConfig => 'Copy configuration';

  @override
  String get pasteImportOverrides => 'Paste and import';

  @override
  String get importOverrideConfig => 'Import request override configuration';

  @override
  String get pasteOverrideConfigHint =>
      'Paste an exported JSON configuration. An invalid import does not change the current configuration.';

  @override
  String get overrideConfigCopied => 'Request override configuration copied';

  @override
  String get overrideConfigImported =>
      'Request override configuration imported';

  @override
  String get invalidOverrideConfig => 'Invalid request override configuration';

  @override
  String get appSubtitle => 'Local Python script runtime';

  @override
  String get pythonPath => 'Python path';

  @override
  String get technicalArchitecture => 'Technical architecture';

  @override
  String get framework => 'Framework';

  @override
  String get nativeLayer => 'Native layer';

  @override
  String get storage => 'Storage';

  @override
  String get runtimeRequirements => 'Requirements';

  @override
  String get architectureFrameworkValue =>
      'Flutter + Dart · Material 3 · Riverpod / Provider';

  @override
  String get architectureEngineValue =>
      'Switchable Chaquopy / Linux-like (Debian proot)';

  @override
  String get architectureNativeValue =>
      'Kotlin · MethodChannel, EventChannel, and Pigeon';

  @override
  String get architectureStorageValue =>
      'SharedPreferences + SQLite + file system';

  @override
  String get architectureRequirementsValue => 'Android 8.0+ · arm64-v8a';
}
