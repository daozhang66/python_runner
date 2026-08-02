import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import '../../../../providers/execution_provider.dart';
import '../../../../ui/app_state_views.dart';
import '../../../../utils/app_page_transitions.dart';
import '../../../console/presentation/pages/run_console_page.dart';
import '../../../../l10n/app_localizations.dart';

class ScriptEditorPage extends ConsumerStatefulWidget {
  final String scriptName;
  const ScriptEditorPage({super.key, required this.scriptName});

  @override
  ConsumerState<ScriptEditorPage> createState() => _ScriptEditorPageState();
}

class _ScriptEditorPageState extends ConsumerState<ScriptEditorPage> {
  static final _modifiedAtFormat = DateFormat('yyyy-MM-dd HH:mm');
  late CodeLineEditingController _controller;
  CodeFindController? _findController;
  late final SelectionToolbarController _toolbarController;
  bool _loading = true;
  bool _modified = false;
  bool _readOnly = true;
  double _fontSize = 10.0;
  double? _scaleStartFontSize;
  final Map<int, Offset> _scalePointers = {};
  double? _pointerScaleStartDistance;
  String _savedText = '';

  static const _minFontSize = 6.0;
  static const _maxFontSize = 36.0;

  String get _displayName => widget.scriptName.replaceAll('.py', '');

  String _formatModifiedAt(BuildContext context, DateTime? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.modifiedAtUnknown;
    return l10n.modifiedAt(_modifiedAtFormat.format(value));
  }

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController();
    _findController = CodeFindController(_controller);
    _toolbarController = _buildSelectionToolbarController();
    _loadContent();
  }

  SelectionToolbarController _buildSelectionToolbarController() {
    return MobileSelectionToolbarController(
      builder: ({
        required TextSelectionToolbarAnchors anchors,
        required BuildContext context,
        required CodeLineEditingController controller,
        required VoidCallback onDismiss,
        required VoidCallback onRefresh,
      }) {
        final buttonItems = <ContextMenuButtonItem>[];

        if (!controller.isEmpty) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.copy,
              onPressed: () async {
                await controller.copy();
                onDismiss();
              },
            ),
          );
        }

        if (!_readOnly && !controller.isEmpty) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.cut,
              onPressed: () {
                controller.cut();
                onDismiss();
              },
            ),
          );
        }

        if (!_readOnly) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.paste,
              onPressed: () {
                controller.paste();
                onDismiss();
              },
            ),
          );
        }

        if (!controller.isEmpty && !controller.isAllSelected) {
          buttonItems.add(
            ContextMenuButtonItem(
              type: ContextMenuButtonType.selectAll,
              onPressed: () {
                controller.selectAll();
                onRefresh();
              },
            ),
          );
        }

        if (buttonItems.isEmpty) {
          return const SizedBox.shrink();
        }

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: buttonItems,
        );
      },
    );
  }

  Future<void> _loadContent() async {
    final scriptProvider = ref.read(scriptWorkspaceControllerProvider.notifier);
    final prefs = await SharedPreferences.getInstance();
    final content = await scriptProvider.readScript(widget.scriptName);
    if (!mounted) return;
    _savedText = content;
    _controller.text = content;
    _controller.addListener(_onTextChanged);
    setState(() {
      _fontSize =
          prefs.getDouble('editor_font_size_${widget.scriptName}') ?? 10.0;
      _modified = false;
      _loading = false;
    });
  }

  Future<void> _persistFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('editor_font_size_${widget.scriptName}', _fontSize);
  }

  double? _currentPointerDistance() {
    if (_scalePointers.length < 2) return null;
    final positions = _scalePointers.values.take(2).toList(growable: false);
    return (positions[0] - positions[1]).distance;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _scalePointers[event.pointer] = event.localPosition;
    if (_scalePointers.length == 2) {
      _scaleStartFontSize = _fontSize;
      _pointerScaleStartDistance = _currentPointerDistance();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_scalePointers.containsKey(event.pointer)) return;
    _scalePointers[event.pointer] = event.localPosition;
    final startSize = _scaleStartFontSize;
    final startDistance = _pointerScaleStartDistance;
    final currentDistance = _currentPointerDistance();
    if (startSize == null ||
        startDistance == null ||
        currentDistance == null ||
        startDistance <= 0) {
      return;
    }
    final nextSize = (startSize * currentDistance / startDistance)
        .clamp(_minFontSize, _maxFontSize)
        .toDouble();
    if ((nextSize - _fontSize).abs() < 0.1) return;
    setState(() => _fontSize = nextSize);
  }

  void _finishPointerScale() {
    if (_scaleStartFontSize != null) {
      _scaleStartFontSize = null;
      _pointerScaleStartDistance = null;
      unawaited(_persistFontSize());
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _scalePointers.remove(event.pointer);
    if (_scalePointers.length < 2) _finishPointerScale();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _scalePointers.remove(event.pointer);
    if (_scalePointers.length < 2) _finishPointerScale();
  }

  void _onTextChanged() {
    final currentModified = _controller.text != _savedText;
    if (currentModified == _modified) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestModified = _controller.text != _savedText;
      if (latestModified != _modified) {
        setState(() => _modified = latestModified);
      }
    });
  }

  Future<void> _save() async {
    final success = await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .saveScript(widget.scriptName, _controller.text);
    if (success && mounted) {
      _savedText = _controller.text;
      setState(() => _modified = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.saved),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<bool> _saveSilently() async {
    final success = await ref
        .read(scriptWorkspaceControllerProvider.notifier)
        .saveScript(widget.scriptName, _controller.text);
    if (success && mounted) {
      _savedText = _controller.text;
      setState(() => _modified = false);
    }
    return success;
  }

  Future<void> _run() async {
    try {
      if (_modified) {
        final saved = await _saveSilently();
        if (!saved || !mounted) return;
      }
      final scriptProvider =
          ref.read(scriptWorkspaceControllerProvider.notifier);
      final execProvider = context.read<ExecutionProvider>();
      await scriptProvider.incrementRunCount(widget.scriptName);
      execProvider.clearLogs();
      await execProvider.executeScript(widget.scriptName);
      if (mounted) {
        Navigator.push(
          context,
          AppPageTransitions.scaleIn(
            RunConsolePage(scriptName: widget.scriptName),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.runFailed(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildCommandBar() {
    if (_readOnly) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: l10n.editorActions,
            onSelected: (value) {
              switch (value) {
                case 'indent':
                  _controller.applyIndent();
                  break;
                case 'outdent':
                  _controller.applyOutdent();
                  break;
                case 'undo':
                  _controller.undo();
                  break;
                case 'redo':
                  _controller.redo();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'indent',
                child: Row(children: [
                  Icon(Icons.format_indent_increase),
                  SizedBox(width: 12),
                  Text(l10n.indent),
                ]),
              ),
              PopupMenuItem(
                value: 'outdent',
                child: Row(children: [
                  Icon(Icons.format_indent_decrease),
                  SizedBox(width: 12),
                  Text(l10n.outdent),
                ]),
              ),
              PopupMenuItem(
                value: 'undo',
                child: Row(children: [
                  Icon(Icons.undo),
                  SizedBox(width: 12),
                  Text(l10n.undo),
                ]),
              ),
              PopupMenuItem(
                value: 'redo',
                child: Row(children: [
                  Icon(Icons.redo),
                  SizedBox(width: 12),
                  Text(l10n.redo),
                ]),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_note, size: 20),
                  const SizedBox(width: 6),
                  Text(l10n.editorActions),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            _modified
                ? AppLocalizations.of(context)!.unsaved
                : AppLocalizations.of(context)!.synced,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildEditorStatusBar() {
    final colors = Theme.of(context).colorScheme;
    final modifiedAt = ref.watch(
      scriptWorkspaceControllerProvider.select<DateTime?>((state) {
        for (final script in state.scripts) {
          if (script.name == widget.scriptName) {
            return script.modifiedAt;
          }
        }
        return null;
      }),
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          Text(
            _modified
                ? AppLocalizations.of(context)!.modified
                : AppLocalizations.of(context)!.saved,
            style: TextStyle(
              fontSize: 11,
              color: _modified ? colors.primary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _readOnly
                ? AppLocalizations.of(context)!.readOnlyMode
                : AppLocalizations.of(context)!.editingMode,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            '${_fontSize.toStringAsFixed(0)} px · ${_formatModifiedAt(context, modifiedAt)}',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isThisRunning = context.select<ExecutionProvider, bool>(
      (p) => p.isRunning && p.currentScriptName == widget.scriptName,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          if (_modified)
            IconButton(
                icon: const Icon(Icons.save),
                onPressed: _save,
                tooltip: l10n.save),
          IconButton(
            icon: Icon(isThisRunning ? Icons.stop : Icons.play_arrow),
            onPressed: isThisRunning
                ? () => context.read<ExecutionProvider>().stopExecution()
                : _run,
            tooltip: isThisRunning ? l10n.stop : l10n.run,
          ),
          PopupMenuButton<String>(
            tooltip: l10n.more,
            onSelected: (value) {
              switch (value) {
                case 'mode':
                  setState(() => _readOnly = !_readOnly);
                  break;
                case 'search':
                  _findController?.findMode();
                  break;
                case 'console':
                  Navigator.push(
                    context,
                    AppPageTransitions.fadeThrough(
                      RunConsolePage(scriptName: widget.scriptName),
                    ),
                  );
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'mode',
                child: Row(children: [
                  Icon(_readOnly ? Icons.lock_open : Icons.lock),
                  const SizedBox(width: 12),
                  Text(_readOnly ? l10n.enterEditMode : l10n.switchToReadOnly),
                ]),
              ),
              PopupMenuItem(
                value: 'search',
                child: Row(children: [
                  const Icon(Icons.search),
                  const SizedBox(width: 12),
                  Text(l10n.search),
                ]),
              ),
              PopupMenuItem(
                value: 'console',
                child: Row(children: [
                  const Icon(Icons.fullscreen),
                  const SizedBox(width: 12),
                  Text(l10n.fullScreenTerminal),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? AppLoadingState(label: l10n.openingScript)
          : Column(
              children: [
                _buildCommandBar(),
                Expanded(
                  child: RepaintBoundary(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: CodeEditor(
                        controller: _controller,
                        findController: _findController,
                        toolbarController: _toolbarController,
                        readOnly: _readOnly,
                        showCursorWhenReadOnly: false,
                        style: CodeEditorStyle(
                          fontFamily: 'monospace',
                          fontSize: _fontSize,
                          codeTheme: CodeHighlightTheme(
                            languages: {
                              'python': CodeHighlightThemeMode(
                                mode: langPython,
                              ),
                            },
                            theme: isDark ? vs2015Theme : vsTheme,
                          ),
                        ),
                        wordWrap: false,
                        indicatorBuilder: (context, editingController,
                            chunkController, notifier) {
                          return Row(
                            children: [
                              DefaultCodeLineNumber(
                                controller: editingController,
                                notifier: notifier,
                              ),
                            ],
                          );
                        },
                        findBuilder: (context, controller, readOnly) {
                          return CodeFindPanelView(
                            controller: controller,
                            readOnly: readOnly,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _buildEditorStatusBar(),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _findController?.close();
    super.dispose();
  }
}

/// Search/replace panel for CodeEditor.
class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Size get preferredSize => Size(
        double.infinity,
        controller.value == null ? 0 : 40,
      );

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) {
      return const SizedBox(width: 0, height: 0);
    }
    final value = controller.value!;
    final result = value.result == null
        ? 'No results'
        : '${value.result!.index + 1}/${value.result!.matches.length}';
    return Container(
      margin: const EdgeInsets.only(right: 10),
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: SizedBox(
        width: 320,
        child: Row(
          children: [
            SizedBox(
              width: 150,
              height: 32,
              child: TextField(
                maxLines: 1,
                focusNode: controller.findInputFocusNode,
                controller: controller.findInputController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.search,
                  filled: true,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(gapPadding: 0),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(result, style: const TextStyle(fontSize: 11)),
            const Spacer(),
            IconButton(
              onPressed: value.result == null
                  ? null
                  : () => controller.previousMatch(),
              icon: const Icon(Icons.arrow_upward, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: AppLocalizations.of(context)!.previous,
            ),
            IconButton(
              onPressed:
                  value.result == null ? null : () => controller.nextMatch(),
              icon: const Icon(Icons.arrow_downward, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: AppLocalizations.of(context)!.next,
            ),
            IconButton(
              onPressed: () => controller.close(),
              icon: const Icon(Icons.close, size: 14),
              constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
              splashRadius: 14,
              tooltip: AppLocalizations.of(context)!.close,
            ),
          ],
        ),
      ),
    );
  }
}
