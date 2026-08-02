import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/script_group.dart';
import '../../../../providers/execution_provider.dart';
import 'package:python_runner/features/scripts/application/script_workspace_controller.dart';
import '../../../../services/native_bridge.dart';
import '../../../../services/script_project_service.dart';
import '../../../../utils/app_page_transitions.dart';
import '../../../console/presentation/pages/run_console_page.dart';
import 'script_editor_page.dart';
import '../../../../l10n/app_localizations.dart';

class ProjectFileEditorPage extends ConsumerStatefulWidget {
  final ScriptGroup group;
  final String filePath;
  final VoidCallback? onSaved;

  const ProjectFileEditorPage({
    super.key,
    required this.group,
    required this.filePath,
    this.onSaved,
  });

  @override
  ConsumerState<ProjectFileEditorPage> createState() =>
      _ProjectFileEditorPageState();
}

class _ProjectFileEditorPageState extends ConsumerState<ProjectFileEditorPage> {
  static final _modifiedAtFormat = DateFormat('yyyy-MM-dd HH:mm');
  late final ScriptProjectService _service;
  late final CodeLineEditingController _controller;
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
  DateTime? _lastModifiedAt;

  static const _minFontSize = 6.0;
  static const _maxFontSize = 36.0;

  String get _title => widget.filePath.split('/').last;

  String _formatModifiedAt(BuildContext context, DateTime? value) {
    final l10n = AppLocalizations.of(context)!;
    if (value == null) return l10n.modifiedAtUnknown;
    return l10n.modifiedAt(_modifiedAtFormat.format(value));
  }

  Future<DateTime?> _loadCurrentFileModifiedAt() async {
    final files = await _service.loadProjectFiles(widget.group);
    for (final file in files) {
      if (file.path == widget.filePath) {
        return file.modifiedAt;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _service = ScriptProjectService(NativeBridge());
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

        if (buttonItems.isEmpty) return const SizedBox.shrink();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: anchors,
          buttonItems: buttonItems,
        );
      },
    );
  }

  Future<void> _loadContent() async {
    final prefs = await SharedPreferences.getInstance();
    final content =
        await _service.readProjectFile(widget.group, widget.filePath);
    final modifiedAt = await _loadCurrentFileModifiedAt();
    if (!mounted) return;
    _savedText = content;
    _controller.text = content;
    _controller.addListener(_onTextChanged);
    setState(() {
      _fontSize = prefs.getDouble('project_editor_font_size') ?? 10.0;
      _lastModifiedAt = modifiedAt;
      _modified = false;
      _loading = false;
    });
  }

  Future<void> _persistFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('project_editor_font_size', _fontSize);
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
    final success = await _service.saveProjectFile(
      widget.group,
      widget.filePath,
      _controller.text,
    );
    if (!success || !mounted) return;
    final modifiedAt = await _loadCurrentFileModifiedAt();
    if (!mounted) return;
    _savedText = _controller.text;
    widget.onSaved?.call();
    setState(() {
      _modified = false;
      _lastModifiedAt = modifiedAt ?? DateTime.now();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.saved),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<bool> _saveSilently() async {
    final success = await _service.saveProjectFile(
      widget.group,
      widget.filePath,
      _controller.text,
    );
    if (success && mounted) {
      final modifiedAt = await _loadCurrentFileModifiedAt();
      if (!mounted) return false;
      _savedText = _controller.text;
      widget.onSaved?.call();
      setState(() {
        _modified = false;
        _lastModifiedAt = modifiedAt ?? DateTime.now();
      });
    }
    return success;
  }

  Future<void> _runProject() async {
    try {
      if (_modified) {
        final saved = await _saveSilently();
        if (!saved || !mounted) return;
      }
      final executionProvider = context.read<ExecutionProvider>();
      executionProvider.clearLogs();
      await executionProvider.executeScriptProject(widget.group);
      if (!mounted) return;
      if (!executionProvider.isRunning) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.projectLaunchFailed)),
        );
        return;
      }
      await ref
          .read(scriptWorkspaceControllerProvider.notifier)
          .markProjectGroupUsed(widget.group);
      if (!mounted) return;
      Navigator.push(
        context,
        AppPageTransitions.scaleIn(
          RunConsolePage(
            scriptName: widget.group.name,
            projectGroup: widget.group,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.runFailed(e))),
      );
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
            '${_fontSize.toStringAsFixed(0)} px · ${_formatModifiedAt(context, _lastModifiedAt)}',
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
    final isThisProjectRunning = context.select<ExecutionProvider, bool>(
      (p) => p.isRunning && p.currentScriptName == widget.group.name,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canRun = widget.group.mainFilePath != null &&
        widget.group.mainFilePath!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_modified)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: l10n.save,
            ),
          if (canRun)
            IconButton(
              icon: Icon(isThisProjectRunning ? Icons.stop : Icons.play_arrow),
              onPressed: isThisProjectRunning
                  ? () => context.read<ExecutionProvider>().stopExecution()
                  : _runProject,
              tooltip: isThisProjectRunning ? l10n.stop : l10n.runProject,
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
                      RunConsolePage(
                        scriptName: widget.group.name,
                        projectGroup: widget.group,
                      ),
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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCommandBar(),
                Expanded(
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
                            'python': CodeHighlightThemeMode(mode: langPython),
                          },
                          theme: isDark ? vs2015Theme : vsTheme,
                        ),
                      ),
                      wordWrap: false,
                      indicatorBuilder: (
                        context,
                        editingController,
                        chunkController,
                        notifier,
                      ) {
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
