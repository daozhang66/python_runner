import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// GPU resources belong to one bar; only the immutable program is shared.
class NavigationGlassResources extends ChangeNotifier {
  /// The track is deliberately more opaque and softer than the active lens.
  /// This keeps page cards from remaining legible behind the navigation bar.
  static const trackBlurSigma = 5.0;
  // Logical bevel depth, separate from content magnification. The curved
  // surface and pinch warp refract live scene boundaries into the lens.
  static const lensDepth = 8.0;
  static const lensZoom = 1.035;
  static const lensDispersion = 0.65;
  NavigationGlassResources({
    bool? supported,
    Future<ui.FragmentProgram> Function()? loadProgram,
  })  : _supported = supported ?? ui.ImageFilter.isShaderFilterSupported,
        _loadProgram = loadProgram ?? _loadCachedProgram;

  static const asset = 'assets/shaders/navigation_glass.frag';
  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram> _loadCachedProgram() =>
      _program ??= ui.FragmentProgram.fromAsset(asset);

  final bool _supported;
  final Future<ui.FragmentProgram> Function() _loadProgram;
  ui.FragmentShader? _surface;
  ui.FragmentShader? _lens;
  bool _disposed = false;
  bool _started = false;
  bool get available => _surface != null && _lens != null;

  Future<void> initialize() async {
    if (_started || !_supported || _disposed) return;
    _started = true;
    try {
      final program = await _loadProgram();
      if (_disposed) return;
      _surface = program.fragmentShader();
      _lens = program.fragmentShader();
      // Validate once, before the resources become visible to a widget build.
      ui.ImageFilter.shader(_surface!);
      ui.ImageFilter.shader(_lens!);
    } catch (error) {
      _release();
      if (!_disposed) debugPrint('Navigation glass fallback: $error');
    }
    if (!_disposed) notifyListeners();
  }

  ui.ImageFilter? filter({
    required bool lens,
    required double pixelRatio,
    required double progress,
    required ui.Rect rect,
    required ui.Size viewport,
  }) {
    final shader = lens ? _lens : _surface;
    if (shader == null ||
        rect.isEmpty ||
        viewport.isEmpty ||
        (lens && progress <= 0.001)) {
      return null;
    }
    try {
      // Uniforms 0/1 and sampler 0 are supplied by ImageFilter.shader.
      shader.setFloat(2, pixelRatio);
      shader.setFloat(3, lens ? lensDepth * progress : 2.5);
      shader.setFloat(4, lens ? 1 + (lensZoom - 1) * progress : 1);
      shader.setFloat(5, lens ? lensDispersion * progress : 0);
      shader.setFloat(6, rect.left);
      shader.setFloat(7, rect.top);
      shader.setFloat(8, rect.width);
      shader.setFloat(9, rect.height);
      shader.setFloat(10, viewport.width);
      shader.setFloat(11, viewport.height);
      final activity = progress.clamp(0.0, 1.0);
      shader.setFloat(12, lens ? 1 - (1 - activity) * (1 - activity) : 0);
      return ui.ImageFilter.shader(shader);
    } catch (error) {
      _release();
      debugPrint('Navigation glass fallback: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return null;
    }
  }

  void _release() {
    _surface?.dispose();
    _lens?.dispose();
    _surface = null;
    _lens = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}

/// Update filter coordinates during paint, after ancestor transforms and layout.
/// No snapshots or CPU readback are needed to sample the live scene.
class NavigationGlassBackdrop extends SingleChildRenderObjectWidget {
  const NavigationGlassBackdrop(
      {super.key,
      required this.resources,
      required this.lens,
      required this.progress,
      required this.pixelRatio,
      required this.viewport,
      required super.child});
  final NavigationGlassResources resources;
  final bool lens;
  final double progress;
  final double pixelRatio;
  final Size viewport;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNavigationBackdrop(this);

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderProxyBox renderObject) {
    (renderObject as _RenderNavigationBackdrop).configuration = this;
    renderObject.markNeedsPaint();
  }
}

class _RenderNavigationBackdrop extends RenderProxyBox {
  _RenderNavigationBackdrop(this.configuration);
  NavigationGlassBackdrop configuration;
  final _filterLayer = LayerHandle<BackdropFilterLayer>();
  final _blurLayer = LayerHandle<BackdropFilterLayer>();

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final config = configuration;
    final bounds =
        MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    var filter = config.resources.filter(
        lens: config.lens,
        pixelRatio: config.pixelRatio,
        progress: config.progress,
        rect: bounds,
        viewport: config.viewport);
    if (!config.lens) {
      final blur = ui.ImageFilter.blur(
          sigmaX: NavigationGlassResources.trackBlurSigma,
          sigmaY: NavigationGlassResources.trackBlurSigma);
      if (filter == null) {
        _blurLayer.layer = null;
        filter = blur;
      } else {
        // Blur the clipped surface first. Composing it as the input of an
        // arbitrary shader would force a Gaussian over the whole viewport.
        final blurLayer = _blurLayer.layer ??= BackdropFilterLayer();
        blurLayer.filter = blur;
        blurLayer.blendMode = BlendMode.srcOver;
        context.pushLayer(blurLayer, (_, __) {}, offset);
      }
    }
    if (filter == null) {
      _filterLayer.layer = null;
      super.paint(context, offset);
      return;
    }
    final layer = _filterLayer.layer ??= BackdropFilterLayer();
    layer.filter = filter;
    layer.blendMode = BlendMode.srcOver;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _filterLayer.layer = null;
    _blurLayer.layer = null;
    super.dispose();
  }
}
