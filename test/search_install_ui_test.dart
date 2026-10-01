import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as legacy;
import 'package:python_runner/features/packages/application/package_repository.dart';
import 'package:python_runner/l10n/app_localizations.dart';
import 'package:python_runner/pages/network_inspector_page.dart';
import 'package:python_runner/pages/package_manager_page.dart';
import 'package:python_runner/providers/theme_provider.dart';
import 'package:python_runner/runtime/runtime_package.dart';
import 'package:python_runner/services/http_inspector_store.dart';
import 'package:python_runner/ui/app_theme.dart';
import 'package:python_runner/ui/app_toolbars.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/package_test_helper.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder get _search => find.descendant(
    of: find.byType(AppSearchBar), matching: find.byType(TextField));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in {
      'MiSans': 'assets/fonts/MiSansVF.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(font.key);
      loader.addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'search actions share its background without adding layout padding',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pump(
        tester,
        Scaffold(
            body: AppSearchBar(
          controller: controller,
          onChanged: (_) {},
          onClear: controller.clear,
          trailingActions: [
            for (var i = 0; i < 3; i++)
              IconButton(
                key: ValueKey('test-action-$i'),
                onPressed: () {},
                icon: const Icon(Icons.tune),
              ),
          ],
        )));
    final fieldContainer = find
        .descendant(
          of: find.byType(AppSearchBar),
          matching: find.byWidgetPredicate((widget) =>
              widget is Container && widget.decoration is BoxDecoration),
        )
        .first;
    final groupDecoration = tester
        .widget<DecoratedBox>(find
            .descendant(
              of: _key('search-actions-background'),
              matching: find.byType(DecoratedBox),
            )
            .first)
        .decoration;
    expect(
        groupDecoration, tester.widget<Container>(fieldContainer).decoration);
    final controlsWidth =
        List.generate(3, (i) => tester.getSize(_key('test-action-$i')).width)
            .reduce((a, b) => a + b);
    expect(
        tester.getSize(_key('search-actions-background')).width, controlsWidth);
    expect(find.byTooltip('Clear'), findsNothing);
    controller.text = 'requests';
    await tester.pump();
    expect(find.byTooltip('Clear'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(find.byTooltip('Clear'), findsNothing);
  });

  testWidgets(
      'package search clears and refreshes without changing installation fields',
      (tester) async {
    final repo = await _pumpPackages(tester);
    await tester.enterText(_key('install-package-name'), 'rich');
    await tester.enterText(_search, 'requests');
    await tester.pump();
    expect(find.text('requests'), findsWidgets);
    expect(find.text('numpy'), findsNothing);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('numpy'), findsOneWidget);
    expect(
        tester.widget<TextField>(_key('install-package-name')).controller!.text,
        'rich');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(repo.listPackagesCallCount, greaterThan(1));
  });

  testWidgets(
      'install form preserves parameters and rejects duplicate submissions',
      (tester) async {
    final repo = _WaitingPackageRepository();
    await _pumpPackages(tester, repository: repo);
    await tester.tap(_key('install-package'));
    await tester.pump();
    expect(repo.installCallCount, 0);
    await tester.enterText(_key('install-package-name'), 'rich');
    await tester.enterText(_key('install-package-version'), '13.9.0');
    await tester.pump();
    await tester.tap(_key('install-package'));
    await tester.pump();
    expect(repo.installCallCount, 1);
    expect(repo.lastInstallRequest!.packageName, 'rich');
    expect(repo.lastInstallRequest!.version, '13.9.0');
    expect(
        tester.widget<FilledButton>(_key('install-package')).onPressed, isNull);
    await tester.enterText(_key('install-package-name'), 'second-package');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(repo.installCallCount, 1);
    expect(
        tester.widget<TextField>(_key('install-package-name')).controller!.text,
        'second-package');
    repo.pending.complete(const PackageInstallResult(success: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('install inputs use the shared background without nested frames',
      (tester) async {
    await _pumpPackages(tester);
    for (final key in ['install-package-name', 'install-package-version']) {
      final field = tester.widget<TextField>(_key(key));
      expect(field.decoration!.filled, isFalse);
      expect(field.decoration!.enabledBorder, InputBorder.none);
      expect(field.decoration!.disabledBorder, InputBorder.none);
      expect(field.decoration!.focusedBorder, isA<UnderlineInputBorder>());
      expect(field.style!.fontSize, 14);
      expect(field.textAlignVertical, TextAlignVertical.center);
    }
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('network filters and the visible search text stay synchronized',
      (tester) async {
    final store = await _pumpNetwork(tester);
    await tester.enterText(_search, 'alpha');
    await tester.pump();
    expect(store.filteredRecords, hasLength(1));
    expect(store.filterDomain, 'alpha');
    store.clearFilters();
    await tester.pump();
    expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
    expect(store.filteredRecords, hasLength(2));
    store.setFilterDomain('beta');
    await tester.pump();
    expect(tester.widget<TextField>(_search).controller!.text, 'beta');
    await tester.tap(find.byTooltip('Clear').first);
    await tester.pump();
    expect(store.filterDomain, isEmpty);
  });

  for (final brightness in Brightness.values) {
    testWidgets('package controls ${brightness.name} appearance',
        (tester) async {
      await _pumpPackages(tester,
          brightness: brightness, locale: const Locale('zh'));
      final button = _key('install-package');
      final colors = Theme.of(tester.element(button)).colorScheme;
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(material.color, colors.secondaryContainer);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/package_controls_${brightness.name}.png'));
    }, tags: const ['golden']);

    testWidgets('network search ${brightness.name} appearance', (tester) async {
      await _pumpNetwork(tester,
          brightness: brightness, locale: const Locale('zh'));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/network_search_${brightness.name}.png'));
    }, tags: const ['golden']);
  }

  for (final locale in ['en', 'zh']) {
    testWidgets('package installation retains the original single row: $locale',
        (tester) async {
      await _pumpPackages(tester, locale: Locale(locale));
      expect(tester.takeException(), isNull);
      final name = tester.getRect(_key('install-package-name'));
      final version = tester.getRect(_key('install-package-version'));
      final install = tester.getRect(_key('install-package'));
      expect(name.top, version.top);
      expect(name.top, install.top);
      expect(version.size, const Size(82, 38));
      expect(install.size, const Size(72, 38));
      expect(tester.getSize(_key('install-controls-background')).height, 38);
    });
    testWidgets(
        'network tools keep their original horizontal arrangement: $locale',
        (tester) async {
      await _pumpNetwork(tester, locale: Locale(locale));
      final buttons = find.descendant(
          of: _key('search-actions-background'),
          matching: find.byType(IconButton));
      expect(buttons, findsNWidgets(3));
      final top = tester.getTopLeft(buttons.first).dy;
      for (var i = 1; i < 3; i++) {
        expect(tester.getTopLeft(buttons.at(i)).dy, top);
        expect(tester.getTopLeft(buttons.at(i)).dx,
            greaterThan(tester.getTopLeft(buttons.at(i - 1)).dx));
      }
      expect(tester.takeException(), isNull);
    });
  }
}

const _packages = [
  RuntimePackage(name: 'requests', version: '2.32.3', source: 'user'),
  RuntimePackage(name: 'numpy', version: '2.1.0', source: 'user'),
  RuntimePackage(name: 'pip', version: '24.2', source: 'builtin'),
];

Future<FakePackageRepository> _pumpPackages(
  WidgetTester tester, {
  FakePackageRepository? repository,
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double width = 390,
  double scale = 1,
  double keyboard = 0,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final repo = repository ?? FakePackageRepository(packages: _packages);
  addTearDown(repo.dispose);
  await _pump(
      tester,
      ProviderScope(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        packageRepositoryProvider.overrideWithValue(repo),
      ], child: const PackageManagerPage()),
      brightness: brightness,
      locale: locale,
      width: width,
      scale: scale,
      keyboard: keyboard);
  return repo;
}

Future<HttpInspectorStore> _pumpNetwork(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double width = 390,
  double scale = 1,
  double keyboard = 0,
}) async {
  final directory = Directory.systemTemp.createTempSync('pyrunner-search-ui-');
  final store =
      HttpInspectorStore.test(supportDirectoryProvider: () async => directory);
  await tester.runAsync(() async {
    await store.ensureLoaded();
    for (final host in ['alpha', 'beta']) {
      store.addFromJson({
        'id': host,
        'url': 'https://$host.example/api/status',
        'timestamp': DateTime(2026, 10, 1, 9).millisecondsSinceEpoch,
        'method': 'GET',
        'status_code': 200,
        'duration_ms': 12,
        'library': 'requests',
      });
    }
    await store.flush();
  });
  addTearDown(() {
    store.dispose();
    final root = Directory.systemTemp.absolute.path;
    if (directory.absolute.path
        .startsWith('$root${Platform.pathSeparator}pyrunner-search-ui-')) {
      directory.deleteSync(recursive: true);
    }
  });
  await _pump(
      tester,
      legacy.ChangeNotifierProvider<HttpInspectorStore>.value(
          value: store, child: const NetworkInspectorPage()),
      brightness: brightness,
      locale: locale,
      width: width,
      scale: scale,
      keyboard: keyboard);
  return store;
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
  double width = 390,
  double scale = 1,
  double keyboard = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(
        ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
        fontFamily: 'MiSans'),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: child!,
    ),
    home: page,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class _WaitingPackageRepository extends FakePackageRepository {
  _WaitingPackageRepository() : super(packages: _packages);
  final pending = Completer<PackageInstallResult>();
  @override
  Future<PackageInstallResult> installPackage(PackageInstallRequest request) {
    installCallCount++;
    lastInstallRequest = request;
    return pending.future;
  }
}
