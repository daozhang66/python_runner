import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show UncontrolledProviderScope;

import '../../../main.dart' show appNavigatorKey;
import '../../../services/native_bridge.dart';
import 'mcp_confirmation_gate.dart';

/// Sync the resolved Material theme, including dynamic colors and dark mode.
///
/// It also hosts the global MCP surface (approval dialogs and the AI chat
/// button) around the app when a Riverpod scope exists.
class McpOverlayTheme extends StatefulWidget {
  const McpOverlayTheme({super.key, required this.child});
  final Widget child;

  @override
  State<McpOverlayTheme> createState() => _McpOverlayThemeState();
}

class _McpOverlayThemeState extends State<McpOverlayTheme> {
  ColorScheme? _scheme;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    if (_scheme == scheme ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _scheme = scheme;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _scheme != scheme) return;
      try {
        await NativeBridge().setMcpOverlayStyle(
          surface: scheme.surfaceContainerHigh.toARGB32(),
          foreground: scheme.onSurface.toARGB32(),
          primary: scheme.primary.toARGB32(),
          outline: scheme.outlineVariant.toARGB32(),
        );
      } catch (_) {
        // Theme synchronization must not prevent opening the app.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Widget tests that pump this without a Riverpod scope get the child as is.
    final hasProviders = context
            .getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>() !=
        null;
    if (!hasProviders) return widget.child;
    return McpConfirmationGate(
      navigatorKey: appNavigatorKey,
      child: widget.child,
    );
  }
}
