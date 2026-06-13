import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package manager uses compact install strip and package badges', () {
    final source =
        File('lib/pages/package_manager_page.dart').readAsStringSync();

    expect(source, contains('Widget _buildInstallPanel('));
    expect(source, contains('Widget _buildPackageListTile('));
    expect(source, contains('String _formatVersionLabel(String version)'));
    expect(source, contains("return '版本未知';"));
    expect(source, contains('AppSearchBar('));
    expect(source, contains('AppStatusBadge('));
    expect(source, contains('Widget _buildCompactInstallFields('));
    expect(source, contains('Widget _buildCompactInstallLog('));
    expect(source, contains('Widget _buildSearchAndRefreshRow('));
    expect(source, contains('AppThemeColors.cardSurface(colors)'));
    expect(source, contains("hintText: '包名'"));
    expect(source, contains("hintText: '版本'"));
    expect(source, contains('SizedBox(width: 82'));
    expect(source, contains('AppFilePickerPage.pickFile'));
    expect(source, contains('FilePicker.pickFiles'));
    expect(source, contains('installRequirementsFromContent'));
    expect(source, contains("exactFileName: 'requirements.txt'"));
    expect(source, contains("'requirements.txt'"));
    expect(source, contains('requirements.txt 仅支持 Linux-like'));
    expect(source, contains('Icons.description_outlined'));
    expect(source, contains('width: 72'));
    expect(source, contains('height: 38'));
    expect(source, contains('_buildInstallPanel(provider),'));
    expect(source, contains('_buildSearchAndRefreshRow(provider)'));
    expect(source, contains('provider.loadingPackages'));
    expect(source, contains('LinearProgressIndicator(minHeight: 2)'));
    expect(source, contains('ensurePackagesLoaded()'));
    expect(source, contains('loadPackages(forceRefresh: true)'));
    expect(source, isNot(contains('AppSectionCard(')));
    expect(source, isNot(contains('useStackedLayout')));
    expect(source, isNot(contains('constraints.maxWidth < 720')));
    expect(source, isNot(contains("hintText: '包名 (如 requests)'")));
    expect(source, isNot(contains('if (false) _buildInstallPanel')));
    expect(source, isNot(contains('ignore: dead_code')));
    expect(source, isNot(contains('onChanged: (v) {}')));
  });

  test('home tab refreshes package manager when opening package page', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('void _selectTab(int index)'));
    expect(source,
        contains('context.read<PackageProvider>().ensurePackagesLoaded()'));
    expect(source, contains('onDestinationSelected: _selectTab'));
  });
}
