import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/l10n/app_localizations.dart';

import 'package:python_runner/main.dart';

void main() {
  testWidgets('splash gate keeps splash visible for minimum duration',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SplashGate(
          child: Text('ready-child'),
        ),
      ),
    );

    expect(find.text('Python运行器'), findsOneWidget);
    expect(find.text('ready-child'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Python运行器'), findsOneWidget);
    expect(find.text('ready-child'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ready-child'), findsOneWidget);
  });
}
