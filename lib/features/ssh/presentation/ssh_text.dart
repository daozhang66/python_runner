import 'package:flutter/widgets.dart';

import '../application/terminal/terminal_locale.dart';

/// Minimal zh/en string picker used by the SSH feature.
///
/// Usage: `final t = SshText.of(context); Text(t('保存', 'Save'))`.
class SshText {
  const SshText._(this._english);

  factory SshText.of(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    // Terminal sessions have no BuildContext; give them the app's language.
    TerminalLocale.english = english;
    return SshText._(english);
  }

  final bool _english;

  String call(String zh, String en) => _english ? en : zh;
}
