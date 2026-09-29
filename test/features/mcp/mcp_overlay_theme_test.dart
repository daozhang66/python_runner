import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/mcp/presentation/mcp_overlay_theme.dart';

void main() {
  testWidgets(
      'overlay receives resolved light and dark theme colors without starting service',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.daozhang.py/native_bridge');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final colors =
          ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: colors),
          home: const McpOverlayTheme(child: SizedBox())));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'setMcpOverlayStyle');
      expect(calls.last.arguments, {
        'surface': colors.surfaceContainerHigh.toARGB32(),
        'foreground': colors.onSurface.toARGB32(),
        'primary': colors.primary.toARGB32(),
        'outline': colors.outlineVariant.toARGB32(),
      });
    }
    expect(calls.every((call) => call.method == 'setMcpOverlayStyle'), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });
}
