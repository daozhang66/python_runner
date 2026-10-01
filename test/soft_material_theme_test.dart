import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/ui/app_design_tokens.dart';
import 'package:python_runner/ui/app_settings_section.dart';
import 'package:python_runner/ui/app_surfaces.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_theme_palette.dart';
import 'package:python_runner/widgets/app_dialogs.dart';
import 'package:python_runner/widgets/confirm_dialog.dart';

void main() {
  for (final preset in AppThemePalette.values) {
    for (final brightness in Brightness.values) {
      if (preset.darkOnly && brightness == Brightness.light) continue;
      test('${preset.name} $brightness retains its palette and font', () {
        final colors = preset.isSeedBased
            ? ColorScheme.fromSeed(
                seedColor: brightness == Brightness.dark
                    ? preset.darkSeed!
                    : preset.lightSeed!,
                brightness: brightness,
              )
            : preset.handCraftedScheme(brightness)!;
        final theme = AppTheme.build(colors, fontFamily: 'MiSans');
        expect(theme.colorScheme, colors);
        expect(theme.scaffoldBackgroundColor, colors.surface);
        expect(theme.cardTheme.color, colors.surfaceContainerLow);
        expect(theme.dialogTheme.backgroundColor, colors.surfaceContainerHigh);
        expect(theme.textTheme.bodyMedium!.fontFamily, 'MiSans');
        expect(theme.textTheme.bodyMedium!.letterSpacing, 0);
        final focused =
            theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, colors.primary);
        expect(focused.borderSide.width, 2);
        final error = theme.inputDecorationTheme.focusedErrorBorder!
            as OutlineInputBorder;
        expect(error.borderSide.color, colors.error);
      });
    }
  }

  testWidgets('primary, tonal and disabled buttons keep distinct fills',
      (tester) async {
    final colors = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(colors),
      home: Scaffold(
        body: Column(
          children: [
            FilledButton(onPressed: () {}, child: const Text('Primary')),
            FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
            const FilledButton(onPressed: null, child: Text('Disabled')),
          ],
        ),
      ),
    ));
    Color? fill(String label) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.widgetWithText(FilledButton, label),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;
    expect(fill('Primary'), colors.primary);
    expect(fill('Tonal'), colors.secondaryContainer);
    expect(fill('Disabled')!.a, closeTo(0.12, 1 / 255));
    expect(fill('Disabled')!.withValues(alpha: 1), colors.onSurface);
  });

  testWidgets('settings groups are unframed and keep control order',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const Scaffold(
        body: AppSettingsSection(
          icon: Icons.tune,
          title: 'Settings',
          children: [
            ListTile(title: Text('First')),
            ListTile(title: Text('Second')),
          ],
        ),
      ),
    ));
    expect(find.byType(Card), findsNothing);
    expect(tester.getTopLeft(find.text('First')).dy,
        lessThan(tester.getTopLeft(find.text('Second')).dy));
  });

  testWidgets('settings can restore cards without changing content order',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const Scaffold(
        body: AppSettingsSection(
          framed: true,
          icon: Icons.tune,
          title: 'Settings',
          children: [Text('First'), Text('Second')],
        ),
      ),
    ));
    expect(find.byType(Card), findsOneWidget);
    expect(tester.getTopLeft(find.text('First')).dy,
        lessThan(tester.getTopLeft(find.text('Second')).dy));
  });

  testWidgets('tonal surfaces do not replace legacy workspace surfaces',
      (tester) async {
    final colors = ColorScheme.fromSeed(
        seedColor: Colors.teal, brightness: Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(colors),
      home: const Scaffold(
        body: Column(
          children: [
            AppSurface(child: Text('workspace')),
            AppSurface(tonal: true, child: Text('tool')),
          ],
        ),
      ),
    ));
    BoxDecoration decoration(String text) => tester
        .widget<Container>(find
            .descendant(
              of: find.widgetWithText(AppSurface, text),
              matching: find.byType(Container),
            )
            .first)
        .decoration! as BoxDecoration;
    expect(decoration('workspace').color, AppThemeColors.darkSurface);
    expect(decoration('tool').color, colors.surfaceContainerLow);
  });

  testWidgets('dialog blur preference retains the shared surface color',
      (tester) async {
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue);
    late Color opaque;
    late Color translucent;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(colors),
      home: Builder(builder: (context) {
        opaque = appDialogBackgroundColor(context, false);
        translucent = appDialogBackgroundColor(context, true);
        return const SizedBox.shrink();
      }),
    ));
    expect(opaque, colors.surfaceContainerHigh);
    expect(translucent, colors.surfaceContainerHigh.withValues(alpha: 0.74));
  });

  testWidgets('long confirmation remains scrollable and preserves results',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    final colors = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(colors),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await ConfirmDialog.show(
              context,
              title: 'Delete script?',
              content:
                  List.filled(20, 'This action cannot be undone.').join(' '),
              confirmText: 'Delete',
              cancelText: 'Keep',
              confirmColor: colors.error,
            );
          },
          child: const Text('Open'),
        );
      })),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final confirm =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Delete'));
    expect(confirm.style!.foregroundColor!.resolve({}), colors.error);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
