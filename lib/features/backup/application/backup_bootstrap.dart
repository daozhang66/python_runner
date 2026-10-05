import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_locale_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/app_liquid_host.dart';

import 'backup_providers.dart';

/// This recovery shell intentionally never constructs [child] while the native
/// file journal and SQLite marker disagree. Retrying preserves both stores.
class BackupBootstrap extends ConsumerWidget {
  const BackupBootstrap({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(backupStartupProvider);
    if (startup.hasValue && !startup.isLoading && !startup.hasError) {
      return child;
    }
    final preferences = ref.watch(themeProvider);
    ThemeData theme(Brightness brightness) {
      final colors =
          preferences.selectedPreset?.handCraftedScheme(brightness) ??
          ColorScheme.fromSeed(
            seedColor: preferences.useDynamicColor
                ? preferences.dynamicPrimary ?? preferences.seedColor
                : preferences.seedColor,
            brightness: brightness,
            dynamicSchemeVariant: preferences.schemeVariant,
          );
      return AppTheme.build(
        colors,
        fontFamily: preferences.fontFamilyName,
        visualStyle: preferences.visualStyle,
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: ref.watch(appLocaleProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: preferences.selectedPreset?.darkOnly == true
          ? ThemeMode.dark
          : preferences.mode,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      builder: (context, child) => AppLiquidHost(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: startup.hasError
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppLocalizations.of(context)!
                                  .backupRecoveryRequired,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () =>
                                  ref.invalidate(backupStartupProvider),
                              child: Text(
                                AppLocalizations.of(context)!
                                    .backupRetryRecovery,
                              ),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
