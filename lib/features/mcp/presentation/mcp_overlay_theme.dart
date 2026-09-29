import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../services/native_bridge.dart';

/// Sync the resolved Material theme, including dynamic colors and dark mode.
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
  Widget build(BuildContext context) => widget.child;
}
