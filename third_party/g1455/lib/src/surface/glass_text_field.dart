// A text field on glass: the search field of a bar, or any field that is its
// own glass capsule.
//
// **Most of iOS 26's fields are not glass, and that was measured** (spike
// 33): a standalone `UISearchBar` is a near-opaque white capsule 44 pt tall,
// and a `UITextField` a white rounded rectangle of radius 5 — the grid shows
// through neither as a refraction. A field that sits on a glass card is
// therefore just a field: put an ordinary `EditableText` on the card. What is
// glass in iOS 26 is the search field a bar or a toolbar carries, and that
// is what this is — a 44 pt capsule (the standalone field's height; the
// toolbar's own was not photographed) holding an [EditableText].
//
// What it costs: one surface. The caret blinks twice a second and the text
// changes as it is typed, and neither is a capture — both are inside the
// surface's own subtree, which the capture skips and the layer watch
// excludes (the self-capture rule). That is asserted, not assumed, in
// `glass_text_field_test.dart`: a focused field over a still screen records
// nothing for seconds of blinking.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'glass_components.dart' show kGlassMinTapTarget;
import 'glass_finish.dart';
import 'glass_surface.dart';
import 'glass_theme.dart';

/// The field's height (spike 33: the standalone search field, 44 pt).
const double kGlassFieldHeight = 44;

/// A single line of text in a glass capsule.
class GlassTextField extends StatefulWidget {
  const GlassTextField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.leading,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.obscureText = false,
    this.finish,
    this.cursorColor = const Color(0xFF007AFF),
    super.key,
  });

  /// The search field of a bar: a magnifier ahead of the text, "Search" when
  /// empty, and the keyboard's search action.
  const GlassTextField.search({
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.leading = const _Magnifier(),
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.finish,
    this.cursorColor = const Color(0xFF007AFF),
    super.key,
  }) : keyboardType = TextInputType.text,
       textInputAction = TextInputAction.search,
       obscureText = false;

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Shown, dimmed, while the field is empty.
  final String? placeholder;

  /// Ahead of the text and after it — an icon, a clear button.
  final Widget? leading;
  final Widget? trailing;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool obscureText;

  /// The optics. Null takes the theme's.
  final GlassFinish? finish;

  final Color cursorColor;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GlassThemeData theme = GlassTheme.of(context);
    final GlassFinish finish = widget.finish ?? theme.finish;
    // The label colour the glass is legible under — the same arithmetic as
    // every component's (D184, D204) — and the placeholder at a third of it,
    // iOS's `placeholderText` alpha over its label.
    final Color label = theme.legibility(finish).label;
    final TextStyle base = DefaultTextStyle.of(context).style.copyWith(color: label, fontSize: 17);
    final TextStyle hint = base.copyWith(color: label.withValues(alpha: label.a * 0.3));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kGlassMinTapTarget.height),
        child: SizedBox(
          height: kGlassFieldHeight,
          child: GlassSurface(
            borderRadius: kGlassCapsule,
            finish: widget.finish,
            child: IconTheme.merge(
              data: IconThemeData(color: label.withValues(alpha: label.a * 0.6), size: 20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: <Widget>[
                    if (widget.leading != null) ...<Widget>[widget.leading!, const SizedBox(width: 8)],
                    Expanded(
                      child: Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: <Widget>[
                          if (widget.placeholder != null)
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _controller,
                              builder: (BuildContext context, TextEditingValue value, Widget? _) => value.text.isEmpty
                                  ? Text(widget.placeholder!, style: hint, maxLines: 1, overflow: TextOverflow.clip)
                                  : const SizedBox.shrink(),
                            ),
                          EditableText(
                            controller: _controller,
                            focusNode: _focus,
                            style: base,
                            cursorColor: widget.cursorColor,
                            backgroundCursorColor: const Color(0xFF8E8E93),
                            selectionColor: widget.cursorColor.withValues(alpha: 0.3),
                            keyboardType: widget.keyboardType,
                            textInputAction: widget.textInputAction,
                            autofocus: widget.autofocus,
                            obscureText: widget.obscureText,
                            onChanged: widget.onChanged,
                            onSubmitted: widget.onSubmitted,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...<Widget>[const SizedBox(width: 8), widget.trailing!],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A magnifier drawn rather than taken from a font: the package depends on
/// `widgets` alone, and `Icons.search` is Material's.
class _Magnifier extends StatelessWidget {
  const _Magnifier();

  @override
  Widget build(BuildContext context) {
    final IconThemeData icon = IconTheme.of(context);
    final double size = icon.size ?? 20;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MagnifierPainter(icon.color ?? const Color(0xFF8E8E93))),
    );
  }
}

class _MagnifierPainter extends CustomPainter {
  const _MagnifierPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(Offset(s * 0.42, s * 0.42), s * 0.3, stroke)
      ..drawLine(Offset(s * 0.64, s * 0.64), Offset(s * 0.9, s * 0.9), stroke);
  }

  @override
  bool shouldRepaint(_MagnifierPainter oldDelegate) => oldDelegate.color != color;
}
