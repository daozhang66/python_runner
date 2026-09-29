import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/vs.dart';
import 'package:re_highlight/styles/vs2015.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../models/app_file_entry.dart';
import '../../../scripts/presentation/pages/script_editor_page.dart';
import '../../application/file_manager_controller.dart';

/// Full-screen code viewer/editor for files opened from the file manager.
///
/// .py and .json files get syntax highlighting; other text files open as
/// plain code. Editing is opt-in through the readonly toggle, and saving
/// writes back to the same absolute path.
class FileManagerFileViewerPage extends StatefulWidget {
  final AppFileEntry entry;
  final FileManagerController controller;

  /// Optional external editor controller so tests can drive the text.
  /// The page disposes only a controller it created itself.
  final CodeLineEditingController? editorController;

  const FileManagerFileViewerPage({
    super.key,
    required this.entry,
    required this.controller,
    this.editorController,
  });

  @override
  State<FileManagerFileViewerPage> createState() =>
      _FileManagerFileViewerPageState();
}

class _FileManagerFileViewerPageState extends State<FileManagerFileViewerPage> {
  late final CodeLineEditingController _editorController =
      widget.editorController ?? CodeLineEditingController();
  bool get _ownsEditor => widget.editorController == null;
  CodeFindController? _findController;
  late final SelectionToolbarController _toolbarController;
  bool _loading = true;
  bool _isBinary = false;
  bool _modified = false;
  bool _readOnly = true;
  String _savedText = '';

  @override
  void initState() {
    super.initState();
    _findController = CodeFindController(_editorController);
    _toolbarController = MobileSelectionToolbarController(builder: ({
      required BuildContext context,
      required TextSelectionToolbarAnchors anchors,
      required CodeLineEditingController controller,
      required VoidCallback onDismiss,
      required VoidCallback onRefresh,
    }) {
      final buttons = <ContextMenuButtonItem>[
        if (!controller.isEmpty)
          ContextMenuButtonItem(type: ContextMenuButtonType.copy,
            onPressed: () async { await controller.copy(); onDismiss(); }),
        if (!_readOnly && _canEdit && !controller.isEmpty)
          ContextMenuButtonItem(type: ContextMenuButtonType.cut,
            onPressed: () { controller.cut(); onDismiss(); }),
        if (!_readOnly && _canEdit)
          ContextMenuButtonItem(type: ContextMenuButtonType.paste,
            onPressed: () { controller.paste(); onDismiss(); }),
        if (!controller.isEmpty && !controller.isAllSelected)
          ContextMenuButtonItem(type: ContextMenuButtonType.selectAll,
            onPressed: () { controller.selectAll(); onRefresh(); }),
      ];
      return buttons.isEmpty ? const SizedBox.shrink() :
        AdaptiveTextSelectionToolbar.buttonItems(anchors: anchors, buttonItems: buttons);
    });
    _loadContent();
  }

  @override
  void deactivate() {
    _toolbarController.hide(context);
    super.deactivate();
  }

  @override
  void dispose() {
    _editorController.removeListener(_onTextChanged);
    _findController?.close();
    if (_ownsEditor) {
      _editorController.dispose();
    }
    super.dispose();
  }

  bool get _canEdit => widget.controller.canMutate(widget.entry);

  /// Heuristic: NUL bytes in the head of the file mean binary content.
  static bool _looksBinary(List<int> bytes) {
    return bytes.take(8192).contains(0);
  }

  CodeHighlightTheme? _codeHighlightTheme(bool isDark) {
    final name = widget.entry.name.toLowerCase();
    final languages = <String, CodeHighlightThemeMode>{};
    if (name.endsWith('.py')) {
      languages['python'] = CodeHighlightThemeMode(mode: langPython);
    } else if (name.endsWith('.json')) {
      languages['json'] = CodeHighlightThemeMode(mode: langJson);
    }
    return CodeHighlightTheme(
      languages: languages,
      theme: isDark ? vs2015Theme : vsTheme,
    );
  }

  Future<void> _loadContent() async {
    try {
      final bytes = await widget.controller.readFileBytes(widget.entry);
      if (!mounted) return;
      if (_looksBinary(bytes)) {
        setState(() {
          _isBinary = true;
          _loading = false;
        });
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      _savedText = content;
      _editorController.text = content;
      _editorController.addListener(_onTextChanged);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString(), maxLines: 3)));
    }
  }

  void _onTextChanged() {
    final modified = _editorController.text != _savedText;
    if (modified == _modified) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latest = _editorController.text != _savedText;
      if (latest != _modified) setState(() => _modified = latest);
    });
  }

  Future<void> _save() async {
    try {
      await widget.controller.writeFile(widget.entry, _editorController.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString(), maxLines: 3)));
      return;
    }
    if (!mounted) return;
    _savedText = _editorController.text;
    setState(() => _modified = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.saved),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name),
        actions: [
          if (_modified && !_readOnly)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
              tooltip: l10n.save,
            ),
          if (!_isBinary && !_loading)
            PopupMenuButton<String>(
              tooltip: l10n.more,
              onSelected: (value) {
                switch (value) {
                  case 'mode':
                    _toolbarController.hide(context);
                    setState(() => _readOnly = !_readOnly);
                    break;
                  case 'search':
                    _findController?.findMode();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (_canEdit)
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
              ],
            ),
        ],
      ),
      body: _buildBody(context, l10n, isDark),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    bool isDark,
  ) {
    final colors = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_isBinary) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.file_present, size: 42, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              l10n.unsupportedBinaryFile,
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: CodeEditor(
            controller: _editorController,
            toolbarController: _toolbarController,
            findController: _findController,
            readOnly: _readOnly,
            showCursorWhenReadOnly: false,
            style: CodeEditorStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              codeTheme: _codeHighlightTheme(isDark),
            ),
            wordWrap: false,
            indicatorBuilder: (context, editingController, chunkController,
                notifier) {
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
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
            border: Border(
              top:
                  BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
            ),
          ),
          child: Row(
            children: [
              Text(
                _modified ? l10n.modified : l10n.saved,
                style: TextStyle(
                  fontSize: 11,
                  color: _modified ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _readOnly ? l10n.readOnlyMode : l10n.editingMode,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  widget.entry.path,
                  style:
                      TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
