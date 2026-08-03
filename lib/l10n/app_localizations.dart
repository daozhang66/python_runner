import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Python Runner'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get chinese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @scriptDetails.
  ///
  /// In en, this message translates to:
  /// **'Script details'**
  String get scriptDetails;

  /// No description provided for @selectScript.
  ///
  /// In en, this message translates to:
  /// **'Select a script'**
  String get selectScript;

  /// No description provided for @selectScriptDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a script from the list to view details and quick actions.'**
  String get selectScriptDescription;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @openConsole.
  ///
  /// In en, this message translates to:
  /// **'Open console'**
  String get openConsole;

  /// No description provided for @scriptGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get scriptGroup;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdAt;

  /// No description provided for @lastModified.
  ///
  /// In en, this message translates to:
  /// **'Last modified'**
  String get lastModified;

  /// No description provided for @runCount.
  ///
  /// In en, this message translates to:
  /// **'Run count'**
  String get runCount;

  /// No description provided for @scriptStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get scriptStatus;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get running;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get idle;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @regularScript.
  ///
  /// In en, this message translates to:
  /// **'Regular script'**
  String get regularScript;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @loadingScripts.
  ///
  /// In en, this message translates to:
  /// **'Loading scripts'**
  String get loadingScripts;

  /// No description provided for @loadingPackages.
  ///
  /// In en, this message translates to:
  /// **'Loading installed packages'**
  String get loadingPackages;

  /// No description provided for @loadPackagesFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load packages'**
  String get loadPackagesFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @enableAutoFollow.
  ///
  /// In en, this message translates to:
  /// **'Enable auto-follow'**
  String get enableAutoFollow;

  /// No description provided for @disableAutoFollow.
  ///
  /// In en, this message translates to:
  /// **'Disable auto-follow'**
  String get disableAutoFollow;

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export logs'**
  String get exportLogs;

  /// No description provided for @scripts.
  ///
  /// In en, this message translates to:
  /// **'Scripts'**
  String get scripts;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @packageManager.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get packageManager;

  /// No description provided for @networkRequests.
  ///
  /// In en, this message translates to:
  /// **'Network requests'**
  String get networkRequests;

  /// No description provided for @searchUrlOrDomain.
  ///
  /// In en, this message translates to:
  /// **'Search URL / domain...'**
  String get searchUrlOrDomain;

  /// No description provided for @showNoiseRequests.
  ///
  /// In en, this message translates to:
  /// **'Show DNS/connect/process records'**
  String get showNoiseRequests;

  /// No description provided for @hideNoiseRequests.
  ///
  /// In en, this message translates to:
  /// **'Hide DNS/connect/process records'**
  String get hideNoiseRequests;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @noNetworkRequests.
  ///
  /// In en, this message translates to:
  /// **'No network requests'**
  String get noNetworkRequests;

  /// No description provided for @noMatchingRequests.
  ///
  /// In en, this message translates to:
  /// **'No matching requests'**
  String get noMatchingRequests;

  /// No description provided for @runNetworkScriptHint.
  ///
  /// In en, this message translates to:
  /// **'Run a script that makes network requests to see them here'**
  String get runNetworkScriptHint;

  /// No description provided for @tryClearingFilters.
  ///
  /// In en, this message translates to:
  /// **'Try clearing the filters'**
  String get tryClearingFilters;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @imagePreview.
  ///
  /// In en, this message translates to:
  /// **'Image preview'**
  String get imagePreview;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update now'**
  String get updateNow;

  /// No description provided for @dontRemind.
  ///
  /// In en, this message translates to:
  /// **'Don\'t remind me'**
  String get dontRemind;

  /// No description provided for @releaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get releaseNotes;

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String fileSize(Object size);

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(int count);

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String todayAt(Object time);

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday {time}'**
  String yesterdayAt(Object time);

  /// No description provided for @unknownReleaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release date unknown'**
  String get unknownReleaseDate;

  /// No description provided for @updateLog.
  ///
  /// In en, this message translates to:
  /// **'Update log'**
  String get updateLog;

  /// No description provided for @searchVersionOrNotes.
  ///
  /// In en, this message translates to:
  /// **'Search versions or release notes'**
  String get searchVersionOrNotes;

  /// No description provided for @updateLogLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load update logs'**
  String get updateLogLoadFailed;

  /// No description provided for @openReleaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open release page: {error}'**
  String openReleaseFailed(Object error);

  /// No description provided for @noReleaseLogs.
  ///
  /// In en, this message translates to:
  /// **'No update logs'**
  String get noReleaseLogs;

  /// No description provided for @noMatchingReleaseLogs.
  ///
  /// In en, this message translates to:
  /// **'No matching update logs'**
  String get noMatchingReleaseLogs;

  /// No description provided for @unnamedRelease.
  ///
  /// In en, this message translates to:
  /// **'Unnamed release'**
  String get unnamedRelease;

  /// No description provided for @prerelease.
  ///
  /// In en, this message translates to:
  /// **'Pre-release'**
  String get prerelease;

  /// No description provided for @noReleaseNotes.
  ///
  /// In en, this message translates to:
  /// **'This release has no notes.'**
  String get noReleaseNotes;

  /// No description provided for @releasePage.
  ///
  /// In en, this message translates to:
  /// **'Release page'**
  String get releasePage;

  /// No description provided for @appLogs.
  ///
  /// In en, this message translates to:
  /// **'App logs'**
  String get appLogs;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get clearLogs;

  /// No description provided for @searchLogContent.
  ///
  /// In en, this message translates to:
  /// **'Search log content'**
  String get searchLogContent;

  /// No description provided for @noLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs'**
  String get noLogs;

  /// No description provided for @noMatchingLogs.
  ///
  /// In en, this message translates to:
  /// **'No matching logs'**
  String get noMatchingLogs;

  /// No description provided for @logsCopied.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopied;

  /// No description provided for @clearLogsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all logs? This cannot be undone.'**
  String get clearLogsConfirm;

  /// No description provided for @logsCleared.
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get level;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @lastSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get lastSevenDays;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String hoursAgo(int count);

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @uninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get uninstall;

  /// No description provided for @repair.
  ///
  /// In en, this message translates to:
  /// **'Repair'**
  String get repair;

  /// No description provided for @copyInstallLog.
  ///
  /// In en, this message translates to:
  /// **'Copy installation log'**
  String get copyInstallLog;

  /// No description provided for @installLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Installation log copied'**
  String get installLogCopied;

  /// No description provided for @searchInstalledPackages.
  ///
  /// In en, this message translates to:
  /// **'Search installed packages...'**
  String get searchInstalledPackages;

  /// No description provided for @packageName.
  ///
  /// In en, this message translates to:
  /// **'Package name'**
  String get packageName;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @noPackages.
  ///
  /// In en, this message translates to:
  /// **'No packages'**
  String get noPackages;

  /// No description provided for @noMatchingPackages.
  ///
  /// In en, this message translates to:
  /// **'No matching packages'**
  String get noMatchingPackages;

  /// No description provided for @unknownVersion.
  ///
  /// In en, this message translates to:
  /// **'Unknown version'**
  String get unknownVersion;

  /// No description provided for @userInstalledPackages.
  ///
  /// In en, this message translates to:
  /// **'User installed ({count})'**
  String userInstalledPackages(int count);

  /// No description provided for @builtInPackages.
  ///
  /// In en, this message translates to:
  /// **'Built-in ({count})'**
  String builtInPackages(int count);

  /// No description provided for @uninstallPackage.
  ///
  /// In en, this message translates to:
  /// **'Uninstall package'**
  String get uninstallPackage;

  /// No description provided for @uninstallPackageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Uninstall \"{name}\"?'**
  String uninstallPackageConfirm(Object name);

  /// No description provided for @pythonRunnerSlogan.
  ///
  /// In en, this message translates to:
  /// **'Life is short, use Python'**
  String get pythonRunnerSlogan;

  /// No description provided for @terminalTheme.
  ///
  /// In en, this message translates to:
  /// **'Terminal theme'**
  String get terminalTheme;

  /// No description provided for @darkTerminal.
  ///
  /// In en, this message translates to:
  /// **'Dark terminal'**
  String get darkTerminal;

  /// No description provided for @lightTerminal.
  ///
  /// In en, this message translates to:
  /// **'Light terminal'**
  String get lightTerminal;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @monochromeOutput.
  ///
  /// In en, this message translates to:
  /// **'Monochrome output'**
  String get monochromeOutput;

  /// No description provided for @showLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Show line numbers'**
  String get showLineNumbers;

  /// No description provided for @hideLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Hide line numbers'**
  String get hideLineNumbers;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @searchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search logs...'**
  String get searchLogs;

  /// No description provided for @onlyErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors only'**
  String get onlyErrors;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @noMatchingOutput.
  ///
  /// In en, this message translates to:
  /// **'No matching output'**
  String get noMatchingOutput;

  /// No description provided for @waitingForOutput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for output...'**
  String get waitingForOutput;

  /// No description provided for @noOutput.
  ///
  /// In en, this message translates to:
  /// **'No output'**
  String get noOutput;

  /// No description provided for @newOutputAvailable.
  ///
  /// In en, this message translates to:
  /// **'New output. Tap to jump to the bottom.'**
  String get newOutputAvailable;

  /// No description provided for @inputContent.
  ///
  /// In en, this message translates to:
  /// **'Enter input...'**
  String get inputContent;

  /// No description provided for @waitingForInput.
  ///
  /// In en, this message translates to:
  /// **'Waiting for script input...'**
  String get waitingForInput;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @runAgain.
  ///
  /// In en, this message translates to:
  /// **'Run again'**
  String get runAgain;

  /// No description provided for @waitingForInputStatus.
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get waitingForInputStatus;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @timeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get timeout;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @finished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get finished;

  /// No description provided for @noRun.
  ///
  /// In en, this message translates to:
  /// **'No active run'**
  String get noRun;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Logs exported'**
  String get logsExported;

  /// No description provided for @logsExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Logs exported to {path}'**
  String logsExportedTo(Object path);

  /// No description provided for @copiedAllLines.
  ///
  /// In en, this message translates to:
  /// **'Copied all {count} lines'**
  String copiedAllLines(int count);

  /// No description provided for @exportFailedTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Try again later.'**
  String get exportFailedTryAgain;

  /// No description provided for @manageRuntime.
  ///
  /// In en, this message translates to:
  /// **'Manage runtime'**
  String get manageRuntime;

  /// No description provided for @runtimeInstalled.
  ///
  /// In en, this message translates to:
  /// **'Linux-like runtime is installed'**
  String get runtimeInstalled;

  /// No description provided for @runtimeNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Linux-like runtime is not installed'**
  String get runtimeNotInstalled;

  /// No description provided for @installRuntime.
  ///
  /// In en, this message translates to:
  /// **'Install runtime'**
  String get installRuntime;

  /// No description provided for @repairRuntime.
  ///
  /// In en, this message translates to:
  /// **'Repair runtime'**
  String get repairRuntime;

  /// No description provided for @runtimeInstalledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Linux-like runtime installed'**
  String get runtimeInstalledSuccess;

  /// No description provided for @runtimeAbout.
  ///
  /// In en, this message translates to:
  /// **'About the Linux-like runtime'**
  String get runtimeAbout;

  /// No description provided for @runtimeDescription.
  ///
  /// In en, this message translates to:
  /// **'The Linux-like runtime is experimental and provides a complete Linux environment with broader Python package and tool support.\n\n• Debian base system\n• Python 3 and pip preinstalled\n• Native extension compilation\n• Better compatibility'**
  String get runtimeDescription;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get preparing;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// No description provided for @runtimeDownloadRequirement.
  ///
  /// In en, this message translates to:
  /// **'Downloads about 104 MB of Debian, Python, pip, and build-essential packages'**
  String get runtimeDownloadRequirement;

  /// No description provided for @allFiles.
  ///
  /// In en, this message translates to:
  /// **'All files'**
  String get allFiles;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @upOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get upOneLevel;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @internalStorage.
  ///
  /// In en, this message translates to:
  /// **'Internal storage'**
  String get internalStorage;

  /// No description provided for @systemFilePicker.
  ///
  /// In en, this message translates to:
  /// **'System file picker'**
  String get systemFilePicker;

  /// No description provided for @storageLocations.
  ///
  /// In en, this message translates to:
  /// **'Storage locations'**
  String get storageLocations;

  /// No description provided for @searchFiles.
  ///
  /// In en, this message translates to:
  /// **'Search {filter}'**
  String searchFiles(Object filter);

  /// No description provided for @noBrowsableFiles.
  ///
  /// In en, this message translates to:
  /// **'No files to browse'**
  String get noBrowsableFiles;

  /// No description provided for @noFilesInDirectory.
  ///
  /// In en, this message translates to:
  /// **'No {filter} in this directory'**
  String noFilesInDirectory(Object filter);

  /// No description provided for @systemFilePickerHint.
  ///
  /// In en, this message translates to:
  /// **'Use the system file picker from the top-right corner.'**
  String get systemFilePickerHint;

  /// No description provided for @goUpOrInternalStorageHint.
  ///
  /// In en, this message translates to:
  /// **'Go up one level or return to internal storage.'**
  String get goUpOrInternalStorageHint;

  /// No description provided for @runtimeEngine.
  ///
  /// In en, this message translates to:
  /// **'Runtime engine'**
  String get runtimeEngine;

  /// No description provided for @chaquopyDefault.
  ///
  /// In en, this message translates to:
  /// **'Chaquopy (default)'**
  String get chaquopyDefault;

  /// No description provided for @linuxLikeExperimental.
  ///
  /// In en, this message translates to:
  /// **'Linux-like (experimental)'**
  String get linuxLikeExperimental;

  /// No description provided for @pypiSource.
  ///
  /// In en, this message translates to:
  /// **'PyPI source'**
  String get pypiSource;

  /// No description provided for @useOfficialSourceWhenEmpty.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the official source'**
  String get useOfficialSourceWhenEmpty;

  /// No description provided for @restoreOfficialSource.
  ///
  /// In en, this message translates to:
  /// **'Restore official source'**
  String get restoreOfficialSource;

  /// No description provided for @script.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get script;

  /// No description provided for @executionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Execution timeout'**
  String get executionTimeout;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @workingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Working directory'**
  String get workingDirectory;

  /// No description provided for @defaultWorkingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Default: /storage/emulated/0/Download/PythonRunner'**
  String get defaultWorkingDirectory;

  /// No description provided for @scriptWorkingDirectoryDescription.
  ///
  /// In en, this message translates to:
  /// **'Base directory for script file I/O'**
  String get scriptWorkingDirectoryDescription;

  /// No description provided for @scriptExportDirectory.
  ///
  /// In en, this message translates to:
  /// **'Script export directory'**
  String get scriptExportDirectory;

  /// No description provided for @defaultDownloadDirectory.
  ///
  /// In en, this message translates to:
  /// **'Default: Downloads'**
  String get defaultDownloadDirectory;

  /// No description provided for @networkDebugMode.
  ///
  /// In en, this message translates to:
  /// **'Network debug mode'**
  String get networkDebugMode;

  /// No description provided for @networkDebugModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure proxy and certificate options when enabled'**
  String get networkDebugModeDescription;

  /// No description provided for @allowInsecureCertificates.
  ///
  /// In en, this message translates to:
  /// **'Allow insecure certificates'**
  String get allowInsecureCertificates;

  /// No description provided for @proxyConfigurationOptional.
  ///
  /// In en, this message translates to:
  /// **'Proxy configuration (optional)'**
  String get proxyConfigurationOptional;

  /// No description provided for @proxyConfigurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Network requests will use this proxy'**
  String get proxyConfigurationDescription;

  /// No description provided for @proxyAddress.
  ///
  /// In en, this message translates to:
  /// **'Proxy address'**
  String get proxyAddress;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @recordNetworkRequests.
  ///
  /// In en, this message translates to:
  /// **'Record network requests'**
  String get recordNetworkRequests;

  /// No description provided for @recordNetworkRequestsDescription.
  ///
  /// In en, this message translates to:
  /// **'Capture HTTP, DNS, socket, and common network commands'**
  String get recordNetworkRequestsDescription;

  /// No description provided for @recordResponsePreview.
  ///
  /// In en, this message translates to:
  /// **'Record response previews'**
  String get recordResponsePreview;

  /// No description provided for @enableRequestOverrides.
  ///
  /// In en, this message translates to:
  /// **'Enable request overrides'**
  String get enableRequestOverrides;

  /// No description provided for @systemTools.
  ///
  /// In en, this message translates to:
  /// **'System tools'**
  String get systemTools;

  /// No description provided for @exportFullLogs.
  ///
  /// In en, this message translates to:
  /// **'Export full logs'**
  String get exportFullLogs;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @autoCheckUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates at startup'**
  String get autoCheckUpdates;

  /// No description provided for @downloadMirror.
  ///
  /// In en, this message translates to:
  /// **'Download mirror'**
  String get downloadMirror;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About app'**
  String get aboutApp;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @themeAndColors.
  ///
  /// In en, this message translates to:
  /// **'Theme and colors'**
  String get themeAndColors;

  /// No description provided for @appLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'View and filter system logs, crash logs, and script errors'**
  String get appLogsDescription;

  /// No description provided for @exportFullLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'Export full diagnostics to the working directory or its default'**
  String get exportFullLogsDescription;

  /// No description provided for @checkForUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Get the latest APK from GitHub Releases'**
  String get checkForUpdatesDescription;

  /// No description provided for @updateLogDescription.
  ///
  /// In en, this message translates to:
  /// **'View GitHub Releases history'**
  String get updateLogDescription;

  /// No description provided for @autoCheckUpdatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Check for updates whenever the app starts'**
  String get autoCheckUpdatesDescription;

  /// No description provided for @mirrorNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured (tap to set)'**
  String get mirrorNotConfigured;

  /// No description provided for @themeAndColorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Theme mode, Material You, palettes, custom colors, and fonts'**
  String get themeAndColorsDescription;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'{value} hours'**
  String hours(Object value);

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{value} minutes'**
  String minutes(Object value);

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'{value} seconds'**
  String seconds(Object value);

  /// No description provided for @requestOverrideWarning.
  ///
  /// In en, this message translates to:
  /// **'This globally overrides User-Agent, headers, cookies, timeouts, and other HTTP settings in Python scripts.\n\nIt changes actual script behavior and should only be used for debugging.'**
  String get requestOverrideWarning;

  /// No description provided for @confirmEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get confirmEnable;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @unsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get unsaved;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modified;

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get readOnly;

  /// No description provided for @editorActions.
  ///
  /// In en, this message translates to:
  /// **'Editor actions'**
  String get editorActions;

  /// No description provided for @indent.
  ///
  /// In en, this message translates to:
  /// **'Indent'**
  String get indent;

  /// No description provided for @outdent.
  ///
  /// In en, this message translates to:
  /// **'Outdent'**
  String get outdent;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @enterEditMode.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get enterEditMode;

  /// No description provided for @switchToReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Switch to read-only'**
  String get switchToReadOnly;

  /// No description provided for @fullScreenTerminal.
  ///
  /// In en, this message translates to:
  /// **'Full-screen terminal'**
  String get fullScreenTerminal;

  /// No description provided for @openingScript.
  ///
  /// In en, this message translates to:
  /// **'Opening script'**
  String get openingScript;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @runProject.
  ///
  /// In en, this message translates to:
  /// **'Run project'**
  String get runProject;

  /// No description provided for @newFile.
  ///
  /// In en, this message translates to:
  /// **'New file'**
  String get newFile;

  /// No description provided for @newDirectory.
  ///
  /// In en, this message translates to:
  /// **'New directory'**
  String get newDirectory;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @fileCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get fileCreated;

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create'**
  String get createFailed;

  /// No description provided for @renamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get renamed;

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to rename'**
  String get renameFailed;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete'**
  String get deleteFailed;

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get deleteFile;

  /// No description provided for @deleteDirectory.
  ///
  /// In en, this message translates to:
  /// **'Delete directory'**
  String get deleteDirectory;

  /// No description provided for @deletePathConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{path}\"?'**
  String deletePathConfirm(Object path);

  /// No description provided for @installRequirements.
  ///
  /// In en, this message translates to:
  /// **'Install requirements.txt'**
  String get installRequirements;

  /// No description provided for @requirementsLinuxOnly.
  ///
  /// In en, this message translates to:
  /// **'requirements.txt is only supported by Linux-like'**
  String get requirementsLinuxOnly;

  /// No description provided for @selectRequirements.
  ///
  /// In en, this message translates to:
  /// **'Select requirements.txt'**
  String get selectRequirements;

  /// No description provided for @emptyRequirements.
  ///
  /// In en, this message translates to:
  /// **'requirements.txt is empty or cannot be read'**
  String get emptyRequirements;

  /// No description provided for @emptyRequirementsShort.
  ///
  /// In en, this message translates to:
  /// **'requirements.txt is empty'**
  String get emptyRequirementsShort;

  /// No description provided for @userPackages.
  ///
  /// In en, this message translates to:
  /// **'User installed ({count})'**
  String userPackages(int count);

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing'**
  String get installing;

  /// No description provided for @copyLog.
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get copyLog;

  /// No description provided for @packageMissing.
  ///
  /// In en, this message translates to:
  /// **'Package files missing'**
  String get packageMissing;

  /// No description provided for @damaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get damaged;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @builtIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get builtIn;

  /// No description provided for @reinstallRepair.
  ///
  /// In en, this message translates to:
  /// **'Reinstall and repair'**
  String get reinstallRepair;

  /// No description provided for @addScript.
  ///
  /// In en, this message translates to:
  /// **'Add script'**
  String get addScript;

  /// No description provided for @addGroup.
  ///
  /// In en, this message translates to:
  /// **'Add group'**
  String get addGroup;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @importProjectZip.
  ///
  /// In en, this message translates to:
  /// **'Import project ZIP'**
  String get importProjectZip;

  /// No description provided for @searchScripts.
  ///
  /// In en, this message translates to:
  /// **'Search scripts'**
  String get searchScripts;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @reorderScripts.
  ///
  /// In en, this message translates to:
  /// **'Reorder scripts'**
  String get reorderScripts;

  /// No description provided for @multiSelect.
  ///
  /// In en, this message translates to:
  /// **'Multi-select'**
  String get multiSelect;

  /// No description provided for @showScriptNames.
  ///
  /// In en, this message translates to:
  /// **'Show script names'**
  String get showScriptNames;

  /// No description provided for @hideScriptNames.
  ///
  /// In en, this message translates to:
  /// **'Hide script names'**
  String get hideScriptNames;

  /// No description provided for @searchScriptsHint.
  ///
  /// In en, this message translates to:
  /// **'Search scripts...'**
  String get searchScriptsHint;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noMatches;

  /// No description provided for @noScripts.
  ///
  /// In en, this message translates to:
  /// **'No scripts yet'**
  String get noScripts;

  /// No description provided for @createScriptFromMenu.
  ///
  /// In en, this message translates to:
  /// **'Create a script from the top-right menu'**
  String get createScriptFromMenu;

  /// No description provided for @tryOtherKeywords.
  ///
  /// In en, this message translates to:
  /// **'Try other keywords'**
  String get tryOtherKeywords;

  /// No description provided for @requestDetailsCopied.
  ///
  /// In en, this message translates to:
  /// **'Request details copied'**
  String get requestDetailsCopied;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @requestHeaders.
  ///
  /// In en, this message translates to:
  /// **'Request headers ({count})'**
  String requestHeaders(int count);

  /// No description provided for @requestBody.
  ///
  /// In en, this message translates to:
  /// **'Request body'**
  String get requestBody;

  /// No description provided for @response.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get response;

  /// No description provided for @responseHeaders.
  ///
  /// In en, this message translates to:
  /// **'Response headers ({count})'**
  String responseHeaders(int count);

  /// No description provided for @responseImage.
  ///
  /// In en, this message translates to:
  /// **'Response image'**
  String get responseImage;

  /// No description provided for @responseMedia.
  ///
  /// In en, this message translates to:
  /// **'Response media'**
  String get responseMedia;

  /// No description provided for @responsePreview.
  ///
  /// In en, this message translates to:
  /// **'Response preview'**
  String get responsePreview;

  /// No description provided for @responseBody.
  ///
  /// In en, this message translates to:
  /// **'Response body'**
  String get responseBody;

  /// No description provided for @viewOriginalImage.
  ///
  /// In en, this message translates to:
  /// **'View original image'**
  String get viewOriginalImage;

  /// No description provided for @viewFullContent.
  ///
  /// In en, this message translates to:
  /// **'View full content'**
  String get viewFullContent;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @method.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get method;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @proxy.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get proxy;

  /// No description provided for @sslVerification.
  ///
  /// In en, this message translates to:
  /// **'SSL verification'**
  String get sslVerification;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @statusCode.
  ///
  /// In en, this message translates to:
  /// **'Status code'**
  String get statusCode;

  /// No description provided for @errorType.
  ///
  /// In en, this message translates to:
  /// **'Error type'**
  String get errorType;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error message'**
  String get errorMessage;

  /// No description provided for @mainProgramUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to update main program'**
  String get mainProgramUpdateFailed;

  /// No description provided for @mainProgramSet.
  ///
  /// In en, this message translates to:
  /// **'Main program set'**
  String get mainProgramSet;

  /// No description provided for @mainProgramNotSet.
  ///
  /// In en, this message translates to:
  /// **'Main program not set'**
  String get mainProgramNotSet;

  /// No description provided for @unableToReadZipPath.
  ///
  /// In en, this message translates to:
  /// **'Unable to read ZIP path'**
  String get unableToReadZipPath;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @zipImportComplete.
  ///
  /// In en, this message translates to:
  /// **'ZIP import complete'**
  String get zipImportComplete;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to: {path}'**
  String exportedTo(Object path);

  /// No description provided for @linuxLikeOnly.
  ///
  /// In en, this message translates to:
  /// **'Linux-like only'**
  String get linuxLikeOnly;

  /// No description provided for @installTaskInProgress.
  ///
  /// In en, this message translates to:
  /// **'Installation in progress'**
  String get installTaskInProgress;

  /// No description provided for @projectRequirementsLinuxOnly.
  ///
  /// In en, this message translates to:
  /// **'requirements.txt is only supported by Linux-like'**
  String get projectRequirementsLinuxOnly;

  /// No description provided for @installAlreadyInProgress.
  ///
  /// In en, this message translates to:
  /// **'An installation is already running. Try again later.'**
  String get installAlreadyInProgress;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @projectLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to start project'**
  String get projectLaunchFailed;

  /// No description provided for @exportProjectZip.
  ///
  /// In en, this message translates to:
  /// **'Export project ZIP'**
  String get exportProjectZip;

  /// No description provided for @setMainProgram.
  ///
  /// In en, this message translates to:
  /// **'Set main program'**
  String get setMainProgram;

  /// No description provided for @installDependencies.
  ///
  /// In en, this message translates to:
  /// **'Install dependencies'**
  String get installDependencies;

  /// No description provided for @waitingForInstallLog.
  ///
  /// In en, this message translates to:
  /// **'Waiting for installation log...'**
  String get waitingForInstallLog;

  /// No description provided for @installationComplete.
  ///
  /// In en, this message translates to:
  /// **'Installation complete'**
  String get installationComplete;

  /// No description provided for @installationCompleteRefreshingPackages.
  ///
  /// In en, this message translates to:
  /// **'Installation complete. Refreshing package list...'**
  String get installationCompleteRefreshingPackages;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @projectRootDirectory.
  ///
  /// In en, this message translates to:
  /// **'Project root'**
  String get projectRootDirectory;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(int count);

  /// No description provided for @noFilesInProject.
  ///
  /// In en, this message translates to:
  /// **'No files in this project'**
  String get noFilesInProject;

  /// No description provided for @currentDirectoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'This directory is empty'**
  String get currentDirectoryEmpty;

  /// No description provided for @mainProgram.
  ///
  /// In en, this message translates to:
  /// **'Main program'**
  String get mainProgram;

  /// No description provided for @invalidPath.
  ///
  /// In en, this message translates to:
  /// **'Invalid path: {error}'**
  String invalidPath(Object error);

  /// No description provided for @selectMainProgram.
  ///
  /// In en, this message translates to:
  /// **'Select main program'**
  String get selectMainProgram;

  /// No description provided for @searchPythonFiles.
  ///
  /// In en, this message translates to:
  /// **'Search .py files'**
  String get searchPythonFiles;

  /// No description provided for @noPythonFilesFound.
  ///
  /// In en, this message translates to:
  /// **'No .py files found'**
  String get noPythonFilesFound;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @enterMainProgramPath.
  ///
  /// In en, this message translates to:
  /// **'Enter manually: package/main.py'**
  String get enterMainProgramPath;

  /// No description provided for @doNotSet.
  ///
  /// In en, this message translates to:
  /// **'Do not set'**
  String get doNotSet;

  /// No description provided for @installSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get installSuccess;

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Installation failed: {error}'**
  String installFailed(Object error);

  /// No description provided for @packageUninstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to uninstall {name}'**
  String packageUninstallFailed(Object name);

  /// No description provided for @packageUninstalled.
  ///
  /// In en, this message translates to:
  /// **'{name} uninstalled'**
  String packageUninstalled(Object name);

  /// No description provided for @packageUninstalledDependencies.
  ///
  /// In en, this message translates to:
  /// **'{name} uninstalled and removed {dependencies}'**
  String packageUninstalledDependencies(Object name, Object dependencies);

  /// No description provided for @repairPackage.
  ///
  /// In en, this message translates to:
  /// **'Repair package'**
  String get repairPackage;

  /// No description provided for @repairPackageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reinstall \"{name}\"? A network connection may be required.'**
  String repairPackageConfirm(Object name);

  /// No description provided for @installPythonPackage.
  ///
  /// In en, this message translates to:
  /// **'Install Python packages above'**
  String get installPythonPackage;

  /// No description provided for @noBuiltinPackagesReturned.
  ///
  /// In en, this message translates to:
  /// **'The current runtime returned no built-in packages'**
  String get noBuiltinPackagesReturned;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get themeMode;

  /// No description provided for @selectThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Select theme mode'**
  String get selectThemeMode;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @materialYouWallpaper.
  ///
  /// In en, this message translates to:
  /// **'Use wallpaper dynamic colors'**
  String get materialYouWallpaper;

  /// No description provided for @materialYouOn.
  ///
  /// In en, this message translates to:
  /// **'Android 12+ · Enabled. Colors follow the wallpaper.'**
  String get materialYouOn;

  /// No description provided for @materialYouOff.
  ///
  /// In en, this message translates to:
  /// **'Android 12+ · Disable to use custom colors below.'**
  String get materialYouOff;

  /// No description provided for @presetThemes.
  ///
  /// In en, this message translates to:
  /// **'Preset themes'**
  String get presetThemes;

  /// No description provided for @moreColors.
  ///
  /// In en, this message translates to:
  /// **'More colors'**
  String get moreColors;

  /// No description provided for @deleteColor.
  ///
  /// In en, this message translates to:
  /// **'Delete color'**
  String get deleteColor;

  /// No description provided for @deleteColorConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this custom color?'**
  String get deleteColorConfirm;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get blue;

  /// No description provided for @purple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get purple;

  /// No description provided for @green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get green;

  /// No description provided for @orange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get orange;

  /// No description provided for @pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get pink;

  /// No description provided for @teal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get teal;

  /// No description provided for @red.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get red;

  /// No description provided for @indigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get indigo;

  /// No description provided for @amber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get amber;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced options'**
  String get advancedOptions;

  /// No description provided for @colorSchemeAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Color scheme algorithm'**
  String get colorSchemeAlgorithm;

  /// No description provided for @blurEffect.
  ///
  /// In en, this message translates to:
  /// **'Blur effect'**
  String get blurEffect;

  /// No description provided for @blurEffectDescription.
  ///
  /// In en, this message translates to:
  /// **'Blur dialog backgrounds when supported by the color scheme algorithm'**
  String get blurEffectDescription;

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @selectColorSchemeAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Select color scheme algorithm'**
  String get selectColorSchemeAlgorithm;

  /// No description provided for @selectFont.
  ///
  /// In en, this message translates to:
  /// **'Select font'**
  String get selectFont;

  /// No description provided for @hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// No description provided for @saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// No description provided for @lightness.
  ///
  /// In en, this message translates to:
  /// **'Lightness'**
  String get lightness;

  /// No description provided for @variantTonalSpot.
  ///
  /// In en, this message translates to:
  /// **'Tonal spot (recommended)'**
  String get variantTonalSpot;

  /// No description provided for @variantFidelity.
  ///
  /// In en, this message translates to:
  /// **'Fidelity'**
  String get variantFidelity;

  /// No description provided for @variantContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get variantContent;

  /// No description provided for @variantMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get variantMonochrome;

  /// No description provided for @variantNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get variantNeutral;

  /// No description provided for @variantVibrant.
  ///
  /// In en, this message translates to:
  /// **'Vibrant'**
  String get variantVibrant;

  /// No description provided for @variantExpressive.
  ///
  /// In en, this message translates to:
  /// **'Expressive'**
  String get variantExpressive;

  /// No description provided for @variantRainbow.
  ///
  /// In en, this message translates to:
  /// **'Rainbow'**
  String get variantRainbow;

  /// No description provided for @variantFruitSalad.
  ///
  /// In en, this message translates to:
  /// **'Fruit salad'**
  String get variantFruitSalad;

  /// No description provided for @variantTonalSpotDescription.
  ///
  /// In en, this message translates to:
  /// **'Balanced soft colors for most scenarios'**
  String get variantTonalSpotDescription;

  /// No description provided for @variantFidelityDescription.
  ///
  /// In en, this message translates to:
  /// **'Most faithful to the seed color'**
  String get variantFidelityDescription;

  /// No description provided for @variantContentDescription.
  ///
  /// In en, this message translates to:
  /// **'Prioritizes content readability'**
  String get variantContentDescription;

  /// No description provided for @variantMonochromeDescription.
  ///
  /// In en, this message translates to:
  /// **'Minimal monochrome colors'**
  String get variantMonochromeDescription;

  /// No description provided for @variantNeutralDescription.
  ///
  /// In en, this message translates to:
  /// **'Neutral, low-saturation colors'**
  String get variantNeutralDescription;

  /// No description provided for @variantVibrantDescription.
  ///
  /// In en, this message translates to:
  /// **'Vivid, high-saturation colors'**
  String get variantVibrantDescription;

  /// No description provided for @variantExpressiveDescription.
  ///
  /// In en, this message translates to:
  /// **'Bold, expressive colors'**
  String get variantExpressiveDescription;

  /// No description provided for @variantRainbowDescription.
  ///
  /// In en, this message translates to:
  /// **'Multicolored like a rainbow'**
  String get variantRainbowDescription;

  /// No description provided for @variantFruitSaladDescription.
  ///
  /// In en, this message translates to:
  /// **'A rich fruit-salad palette'**
  String get variantFruitSaladDescription;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select color'**
  String get selectColor;

  /// No description provided for @themeOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get themeOcean;

  /// No description provided for @themeMint.
  ///
  /// In en, this message translates to:
  /// **'Mint'**
  String get themeMint;

  /// No description provided for @themeLilac.
  ///
  /// In en, this message translates to:
  /// **'Lilac'**
  String get themeLilac;

  /// No description provided for @themeHighContrast.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get themeHighContrast;

  /// No description provided for @runFailed.
  ///
  /// In en, this message translates to:
  /// **'Run failed: {error}'**
  String runFailed(Object error);

  /// No description provided for @modifiedAtUnknown.
  ///
  /// In en, this message translates to:
  /// **'Modification time unknown'**
  String get modifiedAtUnknown;

  /// No description provided for @modifiedAt.
  ///
  /// In en, this message translates to:
  /// **'Modified {time}'**
  String modifiedAt(Object time);

  /// No description provided for @readOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get readOnlyMode;

  /// No description provided for @editingMode.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editingMode;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @ungrouped.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get ungrouped;

  /// No description provided for @matchingScriptsCount.
  ///
  /// In en, this message translates to:
  /// **'{visible} of {total} matches'**
  String matchingScriptsCount(int visible, int total);

  /// No description provided for @projectMainProgramSet.
  ///
  /// In en, this message translates to:
  /// **'Project · main program set'**
  String get projectMainProgramSet;

  /// No description provided for @projectMainProgramNotSet.
  ///
  /// In en, this message translates to:
  /// **'Project · main program not set'**
  String get projectMainProgramNotSet;

  /// No description provided for @scriptsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} scripts'**
  String scriptsCount(int count);

  /// No description provided for @runsCount.
  ///
  /// In en, this message translates to:
  /// **'Run {count} times'**
  String runsCount(int count);

  /// No description provided for @notRun.
  ///
  /// In en, this message translates to:
  /// **'Not run'**
  String get notRun;

  /// No description provided for @scriptSemanticLabel.
  ///
  /// In en, this message translates to:
  /// **'Script {name}'**
  String scriptSemanticLabel(Object name);

  /// No description provided for @openScript.
  ///
  /// In en, this message translates to:
  /// **'Open script'**
  String get openScript;

  /// No description provided for @openAndRunScript.
  ///
  /// In en, this message translates to:
  /// **'Open script and run quickly'**
  String get openAndRunScript;

  /// No description provided for @domainFilter.
  ///
  /// In en, this message translates to:
  /// **'Domain: {domain}'**
  String domainFilter(Object domain);

  /// No description provided for @methodFilter.
  ///
  /// In en, this message translates to:
  /// **'Method: {method}'**
  String methodFilter(Object method);

  /// No description provided for @statusFilterError.
  ///
  /// In en, this message translates to:
  /// **'Status: error'**
  String get statusFilterError;

  /// No description provided for @statusFilter.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String statusFilter(Object status);

  /// No description provided for @filterNetworkRequests.
  ///
  /// In en, this message translates to:
  /// **'Filter network requests'**
  String get filterNetworkRequests;

  /// No description provided for @domainOrUrlKeyword.
  ///
  /// In en, this message translates to:
  /// **'Domain / URL keyword'**
  String get domainOrUrlKeyword;

  /// No description provided for @requestMethod.
  ///
  /// In en, this message translates to:
  /// **'Request method'**
  String get requestMethod;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @allRequestsCount.
  ///
  /// In en, this message translates to:
  /// **'All {count}'**
  String allRequestsCount(int count);

  /// No description provided for @visibleRequestsCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {visible} of {total}'**
  String visibleRequestsCount(int visible, int total);

  /// No description provided for @clearNetworkRequests.
  ///
  /// In en, this message translates to:
  /// **'Clear network request records'**
  String get clearNetworkRequests;

  /// No description provided for @clearNetworkRequestsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all captured network request records?'**
  String get clearNetworkRequestsConfirm;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @linuxLikeNotInstalledAction.
  ///
  /// In en, this message translates to:
  /// **'Linux-like is not installed. Open the runtime settings and install it first.'**
  String get linuxLikeNotInstalledAction;

  /// No description provided for @runtimeSwitchLinuxLike.
  ///
  /// In en, this message translates to:
  /// **'Linux-like saved. Execution and package management will use Linux-like.'**
  String get runtimeSwitchLinuxLike;

  /// No description provided for @runtimeSwitchChaquopy.
  ///
  /// In en, this message translates to:
  /// **'Runtime switched to Chaquopy'**
  String get runtimeSwitchChaquopy;

  /// No description provided for @selectRuntimeEngine.
  ///
  /// In en, this message translates to:
  /// **'Select runtime engine'**
  String get selectRuntimeEngine;

  /// No description provided for @chaquopyDescription.
  ///
  /// In en, this message translates to:
  /// **'Stable runtime based on the official Python implementation'**
  String get chaquopyDescription;

  /// No description provided for @linuxLikeDescription.
  ///
  /// In en, this message translates to:
  /// **'Debian environment with support for more packages'**
  String get linuxLikeDescription;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @notInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get notInstalled;

  /// No description provided for @pypiSourceSaved.
  ///
  /// In en, this message translates to:
  /// **'PyPI source saved'**
  String get pypiSourceSaved;

  /// No description provided for @officialSourceRestored.
  ///
  /// In en, this message translates to:
  /// **'Official source restored (https://pypi.org/simple)'**
  String get officialSourceRestored;

  /// No description provided for @downloadMirrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Download acceleration mirror'**
  String get downloadMirrorTitle;

  /// No description provided for @downloadMirrorDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter a GitHub proxy prefix to accelerate APK downloads'**
  String get downloadMirrorDescription;

  /// No description provided for @downloadMirrorEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the original GitHub URL'**
  String get downloadMirrorEmptyHint;

  /// No description provided for @selectScriptExportDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select script export directory'**
  String get selectScriptExportDirectory;

  /// No description provided for @exportDirectorySet.
  ///
  /// In en, this message translates to:
  /// **'Export directory set'**
  String get exportDirectorySet;

  /// No description provided for @selectWorkingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Select working directory'**
  String get selectWorkingDirectory;

  /// No description provided for @workingDirectorySet.
  ///
  /// In en, this message translates to:
  /// **'Working directory set'**
  String get workingDirectorySet;

  /// No description provided for @securityWarning.
  ///
  /// In en, this message translates to:
  /// **'Security warning'**
  String get securityWarning;

  /// No description provided for @insecureCertificateWarning.
  ///
  /// In en, this message translates to:
  /// **'Allowing insecure certificates disables SSL verification and reduces security. Enable this only when debugging with a traffic capture tool.\n\nEnable it?'**
  String get insecureCertificateWarning;

  /// No description provided for @proxyPortMustBeInteger.
  ///
  /// In en, this message translates to:
  /// **'Proxy port must be an integer'**
  String get proxyPortMustBeInteger;

  /// No description provided for @proxyConfigurationSaved.
  ///
  /// In en, this message translates to:
  /// **'Proxy configuration saved'**
  String get proxyConfigurationSaved;

  /// No description provided for @fullLogsExportedTo.
  ///
  /// In en, this message translates to:
  /// **'Full logs exported to: {path}'**
  String fullLogsExportedTo(Object path);

  /// No description provided for @insecureCertificatesOn.
  ///
  /// In en, this message translates to:
  /// **'On — self-signed and capture certificates are trusted (less secure)'**
  String get insecureCertificatesOn;

  /// No description provided for @insecureCertificatesOff.
  ///
  /// In en, this message translates to:
  /// **'Off — SSL certificates are strictly verified'**
  String get insecureCertificatesOff;

  /// No description provided for @responsePreviewLimit.
  ///
  /// In en, this message translates to:
  /// **'First 10 MB of text; images up to 30 MB (uses more memory)'**
  String get responsePreviewLimit;

  /// No description provided for @requestOverridesOn.
  ///
  /// In en, this message translates to:
  /// **'On — global overrides apply to all Python HTTP requests'**
  String get requestOverridesOn;

  /// No description provided for @requestOverridesOff.
  ///
  /// In en, this message translates to:
  /// **'Off — script default request behavior is unchanged'**
  String get requestOverridesOff;

  /// No description provided for @largeResponseCaptured.
  ///
  /// In en, this message translates to:
  /// **'Response body is large. Showing {captured} / {total}.'**
  String largeResponseCaptured(Object captured, Object total);

  /// No description provided for @largeResponse.
  ///
  /// In en, this message translates to:
  /// **'Response body is large. Showing captured content only.'**
  String get largeResponse;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @truncated.
  ///
  /// In en, this message translates to:
  /// **'Truncated'**
  String get truncated;

  /// No description provided for @lineCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String lineCount(int count);

  /// No description provided for @characterCount.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String characterCount(int count);

  /// No description provided for @capturedBytes.
  ///
  /// In en, this message translates to:
  /// **'Captured {captured} / {total}'**
  String capturedBytes(Object captured, Object total);

  /// No description provided for @treeView.
  ///
  /// In en, this message translates to:
  /// **'Tree view'**
  String get treeView;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get exportJson;

  /// No description provided for @jsonTreeView.
  ///
  /// In en, this message translates to:
  /// **'JSON tree view'**
  String get jsonTreeView;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching'**
  String get searching;

  /// No description provided for @searchContent.
  ///
  /// In en, this message translates to:
  /// **'Search content...'**
  String get searchContent;

  /// No description provided for @imageDecodeFailed.
  ///
  /// In en, this message translates to:
  /// **'(Unable to decode image)'**
  String get imageDecodeFailed;

  /// No description provided for @imageRenderFailed.
  ///
  /// In en, this message translates to:
  /// **'(Unable to render image)'**
  String get imageRenderFailed;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @systemLogs.
  ///
  /// In en, this message translates to:
  /// **'System logs'**
  String get systemLogs;

  /// No description provided for @logsCopiedCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current logs copied'**
  String get logsCopiedCurrent;

  /// No description provided for @searchLogsLabel.
  ///
  /// In en, this message translates to:
  /// **'Search logs'**
  String get searchLogsLabel;

  /// No description provided for @searchLogsHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a keyword to filter log content'**
  String get searchLogsHint;

  /// No description provided for @section.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get section;

  /// No description provided for @noMatchingSystemLogs.
  ///
  /// In en, this message translates to:
  /// **'No matching logs'**
  String get noMatchingSystemLogs;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @localPythonRuntime.
  ///
  /// In en, this message translates to:
  /// **'Local Python script runtime'**
  String get localPythonRuntime;

  /// No description provided for @pythonEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Python environment'**
  String get pythonEnvironment;

  /// No description provided for @engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engine;

  /// No description provided for @installDirectory.
  ///
  /// In en, this message translates to:
  /// **'Install directory'**
  String get installDirectory;

  /// No description provided for @path.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get path;

  /// No description provided for @projectHomepage.
  ///
  /// In en, this message translates to:
  /// **'Project homepage'**
  String get projectHomepage;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @scriptName.
  ///
  /// In en, this message translates to:
  /// **'Script name (without .py)'**
  String get scriptName;

  /// No description provided for @groupAdded.
  ///
  /// In en, this message translates to:
  /// **'Group added: {name}'**
  String groupAdded(Object name);

  /// No description provided for @groupCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to create group or group already exists'**
  String get groupCreateFailed;

  /// No description provided for @projectCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Project name already exists or project creation failed'**
  String get projectCreateFailed;

  /// No description provided for @projectCreateError.
  ///
  /// In en, this message translates to:
  /// **'Unable to create project: {error}'**
  String projectCreateError(Object error);

  /// No description provided for @projectImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to import project: {error}'**
  String projectImportFailed(Object error);

  /// No description provided for @onlyPythonFiles.
  ///
  /// In en, this message translates to:
  /// **'Only .py files can be imported'**
  String get onlyPythonFiles;

  /// No description provided for @scriptExists.
  ///
  /// In en, this message translates to:
  /// **'Script already exists'**
  String get scriptExists;

  /// No description provided for @scriptExistsConfirm.
  ///
  /// In en, this message translates to:
  /// **'A script named \"{name}\" already exists. Overwrite it?'**
  String scriptExistsConfirm(Object name);

  /// No description provided for @overwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwrite;

  /// No description provided for @exportToDevice.
  ///
  /// In en, this message translates to:
  /// **'Export to device'**
  String get exportToDevice;

  /// No description provided for @moveToGroup.
  ///
  /// In en, this message translates to:
  /// **'Move to group'**
  String get moveToGroup;

  /// No description provided for @moveToHome.
  ///
  /// In en, this message translates to:
  /// **'Move to home'**
  String get moveToHome;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group...'**
  String get newGroup;

  /// No description provided for @selectedGroupsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} groups selected'**
  String selectedGroupsCount(int count);

  /// No description provided for @selectedItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedItemsCount(int count);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @bulkDeleteGroups.
  ///
  /// In en, this message translates to:
  /// **'Delete groups in bulk'**
  String get bulkDeleteGroups;

  /// No description provided for @bulkExport.
  ///
  /// In en, this message translates to:
  /// **'Export in bulk'**
  String get bulkExport;

  /// No description provided for @bulkDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete in bulk'**
  String get bulkDelete;

  /// No description provided for @finishReordering.
  ///
  /// In en, this message translates to:
  /// **'Finish reordering'**
  String get finishReordering;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @newScriptDescription.
  ///
  /// In en, this message translates to:
  /// **'Create a blank Python script'**
  String get newScriptDescription;

  /// No description provided for @importScriptDescription.
  ///
  /// In en, this message translates to:
  /// **'Select a .py file from the device'**
  String get importScriptDescription;

  /// No description provided for @scriptOverwritten.
  ///
  /// In en, this message translates to:
  /// **'Overwritten: {name}'**
  String scriptOverwritten(Object name);

  /// No description provided for @scriptImported.
  ///
  /// In en, this message translates to:
  /// **'Imported: {name}'**
  String scriptImported(Object name);

  /// No description provided for @exportedScriptsTo.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} scripts to: {path}'**
  String exportedScriptsTo(int count, Object path);

  /// No description provided for @deleteScriptsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected {count} scripts? This cannot be undone.'**
  String deleteScriptsConfirm(int count);

  /// No description provided for @deleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count}'**
  String deleteCount(int count);

  /// No description provided for @scriptsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} scripts'**
  String scriptsDeleted(int count);

  /// No description provided for @groupsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} groups'**
  String groupsDeleted(int count);

  /// No description provided for @deleteScript.
  ///
  /// In en, this message translates to:
  /// **'Delete script'**
  String get deleteScript;

  /// No description provided for @deleteScriptConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteScriptConfirm(Object name);

  /// No description provided for @copyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: {error}'**
  String copyFailed(Object error);

  /// No description provided for @groupsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected {groups} groups and {projects} projects? Project files will also be deleted and scripts in regular groups return home.'**
  String groupsDeleteConfirm(int groups, int projects);

  /// No description provided for @groupsDeleteOnlyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the selected {count} groups? Scripts in those groups return home.'**
  String groupsDeleteOnlyConfirm(int count);

  /// No description provided for @scriptsMovedHome.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} scripts to home'**
  String scriptsMovedHome(int count);

  /// No description provided for @scriptsMovedTo.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} scripts to \"{group}\"'**
  String scriptsMovedTo(int count, Object group);

  /// No description provided for @projectFilesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Project files will also be deleted'**
  String get projectFilesDeleted;

  /// No description provided for @groupScriptsReturnHome.
  ///
  /// In en, this message translates to:
  /// **'Scripts in the group return home'**
  String get groupScriptsReturnHome;

  /// No description provided for @deleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get deleteProject;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @deleteProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete project \"{name}\"? Its files will also be deleted.'**
  String deleteProjectConfirm(Object name);

  /// No description provided for @deleteGroupConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? Scripts in the group return home.'**
  String deleteGroupConfirm(Object name);

  /// No description provided for @checksumUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The SHA-256 integrity check for this release could not be retrieved. Automatic installation is disabled.'**
  String get checksumUnavailable;

  /// No description provided for @checksumUnavailableDetail.
  ///
  /// In en, this message translates to:
  /// **'Reason: {error}'**
  String checksumUnavailableDetail(Object error);

  /// No description provided for @networkRequestSemantics.
  ///
  /// In en, this message translates to:
  /// **'{method} request, {domain}, {status}, duration {duration}, time {time}'**
  String networkRequestSemantics(Object method, Object domain, Object status,
      Object duration, Object time);

  /// No description provided for @requestOverrideSettings.
  ///
  /// In en, this message translates to:
  /// **'Request override settings'**
  String get requestOverrideSettings;

  /// No description provided for @globalOverrides.
  ///
  /// In en, this message translates to:
  /// **'Global overrides'**
  String get globalOverrides;

  /// No description provided for @globalUserAgent.
  ///
  /// In en, this message translates to:
  /// **'User-Agent'**
  String get globalUserAgent;

  /// No description provided for @globalHeaders.
  ///
  /// In en, this message translates to:
  /// **'Global headers (JSON)'**
  String get globalHeaders;

  /// No description provided for @globalCookie.
  ///
  /// In en, this message translates to:
  /// **'Cookie'**
  String get globalCookie;

  /// No description provided for @defaultRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Default request timeout (seconds)'**
  String get defaultRequestTimeout;

  /// No description provided for @noDefaultTimeout.
  ///
  /// In en, this message translates to:
  /// **'0 does not inject a default timeout'**
  String get noDefaultTimeout;

  /// No description provided for @followRedirects.
  ///
  /// In en, this message translates to:
  /// **'Follow redirects'**
  String get followRedirects;

  /// No description provided for @useDebugProxyWhenUnset.
  ///
  /// In en, this message translates to:
  /// **'Use the debug proxy when the script has none'**
  String get useDebugProxyWhenUnset;

  /// No description provided for @noValidDebugProxy.
  ///
  /// In en, this message translates to:
  /// **'Configure a valid proxy in Network debug first'**
  String get noValidDebugProxy;

  /// No description provided for @domainRules.
  ///
  /// In en, this message translates to:
  /// **'Domain rules'**
  String get domainRules;

  /// No description provided for @domainRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Rules are matched in order. The first match overrides global fields with the same name.'**
  String get domainRulesHint;

  /// No description provided for @addDomainRule.
  ///
  /// In en, this message translates to:
  /// **'Add domain rule'**
  String get addDomainRule;

  /// No description provided for @editDomainRule.
  ///
  /// In en, this message translates to:
  /// **'Edit domain rule'**
  String get editDomainRule;

  /// No description provided for @domainPattern.
  ///
  /// In en, this message translates to:
  /// **'Domain or *.example.com'**
  String get domainPattern;

  /// No description provided for @ruleHeaders.
  ///
  /// In en, this message translates to:
  /// **'Rule headers (JSON, optional)'**
  String get ruleHeaders;

  /// No description provided for @noDomainRules.
  ///
  /// In en, this message translates to:
  /// **'No domain rules configured'**
  String get noDomainRules;

  /// No description provided for @testDomain.
  ///
  /// In en, this message translates to:
  /// **'Test domain'**
  String get testDomain;

  /// No description provided for @previewEffectiveOverrides.
  ///
  /// In en, this message translates to:
  /// **'Effective override preview'**
  String get previewEffectiveOverrides;

  /// No description provided for @noMatchingRule.
  ///
  /// In en, this message translates to:
  /// **'No domain rule matches; global settings are used'**
  String get noMatchingRule;

  /// No description provided for @matchedRule.
  ///
  /// In en, this message translates to:
  /// **'Matched rule #{index}'**
  String matchedRule(int index);

  /// No description provided for @saveOverrides.
  ///
  /// In en, this message translates to:
  /// **'Save override settings'**
  String get saveOverrides;

  /// No description provided for @overridesSaved.
  ///
  /// In en, this message translates to:
  /// **'Request overrides saved. They apply when the next script starts.'**
  String get overridesSaved;

  /// No description provided for @copyOverrideConfig.
  ///
  /// In en, this message translates to:
  /// **'Copy configuration'**
  String get copyOverrideConfig;

  /// No description provided for @pasteImportOverrides.
  ///
  /// In en, this message translates to:
  /// **'Paste and import'**
  String get pasteImportOverrides;

  /// No description provided for @importOverrideConfig.
  ///
  /// In en, this message translates to:
  /// **'Import request override configuration'**
  String get importOverrideConfig;

  /// No description provided for @pasteOverrideConfigHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an exported JSON configuration. An invalid import does not change the current configuration.'**
  String get pasteOverrideConfigHint;

  /// No description provided for @overrideConfigCopied.
  ///
  /// In en, this message translates to:
  /// **'Request override configuration copied'**
  String get overrideConfigCopied;

  /// No description provided for @overrideConfigImported.
  ///
  /// In en, this message translates to:
  /// **'Request override configuration imported'**
  String get overrideConfigImported;

  /// No description provided for @invalidOverrideConfig.
  ///
  /// In en, this message translates to:
  /// **'Invalid request override configuration'**
  String get invalidOverrideConfig;

  /// No description provided for @appSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Local Python script runtime'**
  String get appSubtitle;

  /// No description provided for @pythonPath.
  ///
  /// In en, this message translates to:
  /// **'Python path'**
  String get pythonPath;

  /// No description provided for @technicalArchitecture.
  ///
  /// In en, this message translates to:
  /// **'Technical architecture'**
  String get technicalArchitecture;

  /// No description provided for @framework.
  ///
  /// In en, this message translates to:
  /// **'Framework'**
  String get framework;

  /// No description provided for @nativeLayer.
  ///
  /// In en, this message translates to:
  /// **'Native layer'**
  String get nativeLayer;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @runtimeRequirements.
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get runtimeRequirements;

  /// No description provided for @architectureFrameworkValue.
  ///
  /// In en, this message translates to:
  /// **'Flutter + Dart · Material 3 · Riverpod / Provider'**
  String get architectureFrameworkValue;

  /// No description provided for @architectureEngineValue.
  ///
  /// In en, this message translates to:
  /// **'Switchable Chaquopy / Linux-like (Debian proot)'**
  String get architectureEngineValue;

  /// No description provided for @architectureNativeValue.
  ///
  /// In en, this message translates to:
  /// **'Kotlin · MethodChannel, EventChannel, and Pigeon'**
  String get architectureNativeValue;

  /// No description provided for @architectureStorageValue.
  ///
  /// In en, this message translates to:
  /// **'SharedPreferences + SQLite + file system'**
  String get architectureStorageValue;

  /// No description provided for @architectureRequirementsValue.
  ///
  /// In en, this message translates to:
  /// **'Android 8.0+ · arm64-v8a'**
  String get architectureRequirementsValue;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
