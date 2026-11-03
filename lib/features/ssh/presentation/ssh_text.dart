import 'package:flutter/widgets.dart';

/// Minimal zh/en string picker used by the SSH feature.
///
/// Usage: `final t = SshText.of(context); Text(t('保存', 'Save'))`.
class SshText {
  const SshText._(this._english);

  factory SshText.of(BuildContext context) =>
      SshText._(Localizations.localeOf(context).languageCode == 'en');

  final bool _english;

  String call(String zh, String en) => _english ? en : zh;
}
