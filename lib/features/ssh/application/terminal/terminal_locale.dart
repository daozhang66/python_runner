import 'dart:ui' as ui;

/// Language for text that is produced outside widgets (terminal sessions).
///
/// `SshText.of` keeps it in step with the app's language setting; until a
/// screen has been built it follows the phone's language.
class TerminalLocale {
  const TerminalLocale._();

  static bool english =
      ui.PlatformDispatcher.instance.locale.languageCode == 'en';
}

/// Picks the Chinese or English text for the current app language.
String tr(String zh, String en) => TerminalLocale.english ? en : zh;
