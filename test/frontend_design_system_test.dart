import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frontend design system exposes shared tokens', () {
    final tokens = File('lib/ui/app_design_tokens.dart').readAsStringSync();

    expect(tokens, contains('class AppSpacing'));
    expect(tokens, contains('class AppRadius'));
    expect(tokens, contains('class AppMotion'));
    expect(tokens, contains('class AppOpacity'));
    expect(tokens, contains('class AppThemeColors'));
    expect(tokens, contains('darkBackground'));
    expect(tokens, contains('maskedText'));
  });

  test('frontend design system exposes shared UI components', () {
    final surfaces = File('lib/ui/app_surfaces.dart').readAsStringSync();
    final badges = File('lib/ui/app_badges.dart').readAsStringSync();
    final toolbars = File('lib/ui/app_toolbars.dart').readAsStringSync();
    final emptyState = File('lib/ui/app_empty_state.dart').readAsStringSync();

    expect(surfaces, contains('class AppSurface'));
    expect(surfaces, contains('class AppSectionCard'));
    expect(badges, contains('class AppStatusBadge'));
    expect(badges, contains('class AppCountBadge'));
    expect(toolbars, contains('class AppSearchBar'));
    expect(toolbars, contains('class AppToolbarButton'));
    expect(emptyState, contains('class AppEmptyState'));
  });
}
