import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../ui/app_materials.dart';

/// The editor uses preferredSize to keep code below the entire search panel.
class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
    this.textScaler = TextScaler.noScaling,
  });

  final CodeFindController controller;
  final bool readOnly;
  final TextScaler textScaler;

  double get _rowHeight => math.max(48, textScaler.scale(14) + 20);

  @override
  Size get preferredSize => Size(
        double.infinity,
        controller.value == null ? 0 : _rowHeight * 2 + 16,
      );

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    if (value == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final materials = AppMaterials.of(context);
    final matches = value.result?.matches.length ?? 0;
    final canNavigate = !value.searching && matches > 0;
    final result = value.searching
        ? l10n.searching
        : matches == 0
            ? l10n.noMatches
            : '${value.result!.index + 1}/$matches';
    final radius = BorderRadius.circular(materials.liquid ? 16 : 8);

    return SizedBox(
      height: preferredSize.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Align(
          alignment: AlignmentDirectional.topEnd,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppGlassSurface(
              key: const ValueKey('code-find-surface'),
              opaque: true,
              radius: radius,
              // Keep an opaque backing even in the glass style: code scrolls
              // behind this panel and must never show through the controls.
              classicDecoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: radius,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: _rowHeight,
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            focusNode: controller.findInputFocusNode,
                            controller: controller.findInputController,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 14),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) {
                              if (canNavigate) controller.nextMatch();
                            },
                            decoration: InputDecoration(
                              hintText: l10n.search,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: controller.close,
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: l10n.close,
                          style: _actionStyle,
                        ),
                      ]),
                    ),
                    SizedBox(
                      height: _rowHeight,
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              result,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: colors.onSurfaceVariant),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed:
                              canNavigate ? controller.previousMatch : null,
                          icon: const Icon(Icons.arrow_upward, size: 20),
                          tooltip: l10n.previous,
                          style: _actionStyle,
                        ),
                        IconButton(
                          onPressed: canNavigate ? controller.nextMatch : null,
                          icon: const Icon(Icons.arrow_downward, size: 20),
                          tooltip: l10n.next,
                          style: _actionStyle,
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _actionStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.square(48)),
    maximumSize: WidgetStatePropertyAll(Size.square(48)),
    padding: WidgetStatePropertyAll(EdgeInsets.zero),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
