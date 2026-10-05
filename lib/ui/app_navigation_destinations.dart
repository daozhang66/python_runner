import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

abstract final class AppNavigationDestinations {
  static const count = 4;
  static const icons = [
    Icons.code_rounded,
    Icons.http_rounded,
    Icons.inventory_2_rounded,
    Icons.settings_rounded
  ];
  static List<String> labels(AppLocalizations l10n) =>
      [l10n.scripts, l10n.network, l10n.packageManager, l10n.settings];
}
