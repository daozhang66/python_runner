// ignore_for_file: invalid_use_of_protected_member

part of 'script_list_page.dart';

// Script workspace content stays in the presentation library for focused ownership.

extension _ScriptListContent on _ScriptListPageState {
  EdgeInsets get _browsePadding =>
      EdgeInsets.fromLTRB(12, 6, 12, 12 + MediaQuery.paddingOf(context).bottom);

  EdgeInsets get _reorderPadding =>
      EdgeInsets.only(top: 4, bottom: 4 + MediaQuery.paddingOf(context).bottom);

  Widget _buildWorkspaceBody({
    required ScriptWorkspaceController controller,
    required List<dynamic> scripts,
    required bool showFolderHome,
    required String? selectedScriptName,
  }) {
    final content = RefreshIndicator(
      onRefresh: () => controller.load(),
      child: _reorderMode
          ? (showFolderHome
              ? _buildFolderHome(controller)
              : _isGridView
                  ? _buildGridView(scripts)
                  : _buildListView(scripts))
          : _buildBrowseSlivers(controller, scripts, showFolderHome),
    );

    if (!_isTabletWorkspace) return content;

    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 360, maxWidth: 440),
          child: content,
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _buildTabletScriptDetails(controller, selectedScriptName),
        ),
      ],
    );
  }

  Widget _buildTabletScriptDetails(
    ScriptWorkspaceController controller,
    String? selectedScriptName,
  ) {
    final localizations = AppLocalizations.of(context)!;
    if (selectedScriptName == null) {
      return AppEmptyState(
        icon: Icons.code_outlined,
        title: localizations.selectScript,
        subtitle: localizations.selectScriptDescription,
      );
    }
    return Consumer(
      builder: (context, ref, child) {
        final script = ref.watch(
          scriptWorkspaceControllerProvider.select(
            (state) => state.scriptByName(selectedScriptName),
          ),
        );
        if (script == null) return const SizedBox.shrink();
        final group = ref.watch(
          scriptWorkspaceControllerProvider.select(
            (state) => state.groupById(script.groupId),
          ),
        );
        return _ScriptDetailsPanel(
          script: script,
          groupName: group == null
              ? localizations.ungrouped
              : _displayGroupName(group.name),
          localizations: localizations,
          dateFormat: _dateFormat,
          onEdit: () => _openEditor(script.name),
          onRun: () => _runScript(script.name),
          onOpenConsole: () => _openConsole(script.name),
          onTogglePinned: () => _togglePinned(script.name),
        );
      },
    );
  }

  dynamic _findScriptByName(Iterable<dynamic> scripts, String name) {
    for (final script in scripts) {
      if (script.name == name) return script;
    }
    return null;
  }

  Widget _buildSearchResultBar(int totalCount, int visibleCount) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        AppLocalizations.of(context)!
            .matchingScriptsCount(visibleCount, totalCount),
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
    );
  }

  Widget _buildBrowseSlivers(
    ScriptWorkspaceController controller,
    List<dynamic> scripts,
    bool showFolderHome,
  ) {
    final padding = _browsePadding;
    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: AppBreakpoints.scriptGridColumns(context),
      childAspectRatio: 1.44,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );
    final items = showFolderHome
        ? _buildHomeBrowseItems(controller)
        : _buildScriptBrowseItems(scripts);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding,
          sliver: _isGridView
              ? SliverGrid(
                  gridDelegate: gridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => items[index],
                    childCount: items.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => items[index],
                    childCount: items.length,
                  ),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildHomeBrowseItems(
    ScriptWorkspaceController controller,
  ) {
    final items = controller.homeItems;
    return List.generate(items.length, (index) {
      final item = items[index];
      final group = item.group;
      return KeyedSubtree(
        key: ValueKey('home_item_${item.key}'),
        child: group != null
            ? _buildHomeGroupCard(controller, group,
                keyPrefix:
                    _isGridView ? 'sliver_group_grid' : 'sliver_group_list',
                grid: _isGridView)
            : _isGridView
                ? _buildFolderHomeGridScriptCard(item.script!, index,
                    draggable: false)
                : _buildFolderHomeScriptListItem(item.script!, index,
                    reorderIndex: null),
      );
    });
  }

  List<Widget> _buildScriptBrowseItems(List<dynamic> scripts) {
    return List.generate(
      scripts.length,
      (index) {
        final snapshot = scripts[index] as ScriptFile;
        return _ScriptDataScope(
          scriptName: snapshot.name,
          builder: (context, script) {
            final selected = _selectedScripts.contains(script.name);
            if (_isGridView) {
              return _ScriptGridCard(
                key: ValueKey('sliver_script_grid_${script.name}'),
                name: _displayScriptName(script.name, index),
                masked: _maskScriptNames,
                modifiedAt: script.modifiedAt,
                runCount: script.runCount,
                dateFormat: _dateFormat,
                pinned: script.isPinned,
                selected: _multiSelectMode ? selected : null,
                onTap: () => _toggleOrOpenScript(script, selected),
                onLongPress: () => _multiSelectMode
                    ? null
                    : _showContextMenu(script.name, script.isPinned,
                        groupId: script.groupId),
                onRun: _multiSelectMode ? null : () => _runScript(script.name),
              );
            }

            final colors = Theme.of(context).colorScheme;
            return _ScriptCardSurface(
              key: ValueKey('sliver_script_${script.name}'),
              colors: colors,
              selected: _multiSelectMode && selected,
              pinned: script.isPinned,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _toggleOrOpenScript(script, selected),
                onLongPress: _multiSelectMode
                    ? null
                    : () => _showContextMenu(script.name, script.isPinned,
                        groupId: script.groupId),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    children: [
                      if (_multiSelectMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Checkbox(
                            value: selected,
                            onChanged: (_) =>
                                _toggleScriptSelection(script.name),
                          ),
                        )
                      else
                        _ScriptIcon(
                          colors: colors,
                          size: 44,
                          pinned: script.isPinned,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMaskedScriptNameText(
                              _displayScriptName(script.name, index),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _ScriptMetaChip(
                                  colors: colors,
                                  icon: Icons.schedule_rounded,
                                  label: _dateFormat.format(script.modifiedAt),
                                ),
                                _ScriptMetaChip(
                                  colors: colors,
                                  icon: Icons.play_circle_outline_rounded,
                                  label: _formatRunLabel(script.runCount),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!_multiSelectMode)
                        _QuickRunButton(
                            onPressed: () => _runScript(script.name)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleOrOpenScript(dynamic script, bool selected) {
    if (_multiSelectMode) {
      _toggleScriptSelection(script.name);
    } else {
      _handleScriptTap(script.name);
    }
  }

  void _toggleScriptSelection(String name) {
    setState(() {
      if (_selectedScripts.contains(name)) {
        _selectedScripts.remove(name);
      } else {
        _selectedScripts.add(name);
      }
    });
  }

  Widget _buildHomeGroupCard(
    ScriptWorkspaceController controller,
    ScriptGroup group, {
    required String keyPrefix,
    required bool grid,
    bool draggable = false,
  }) {
    final selected = group.id != null && _selectedGroupIds.contains(group.id);
    final dragKey = 'group:${group.id}';
    Widget card({Widget? dragHandle, bool feedback = false}) =>
        _ScriptFolderCard(
          key: feedback ? null : ValueKey('${keyPrefix}_${group.id}'),
          name: _displayGroupName(group.name),
          masked: _maskScriptNames,
          count:
              group.id == null ? 0 : controller.scriptCountInGroup(group.id!),
          isProject: group.isProject,
          hasMainFile: group.mainFilePath != null,
          grid: grid,
          dragHandle: dragHandle,
          selected: _groupSelectMode ? selected : null,
          onTap: feedback
              ? null
              : _groupSelectMode
                  ? () => _toggleGroupSelection(group)
                  : (_multiSelectMode ? null : () => _openGroup(group)),
          onLongPress: feedback || _multiSelectMode
              ? null
              : (_groupSelectMode ? null : () => _showGroupContextMenu(group)),
        );
    if (!draggable || group.id == null) return card();
    final colors = Theme.of(context).colorScheme;
    final handle = grid
        ? Draggable<String>(
            data: dragKey,
            dragAnchorStrategy: (_, __, ___) => const Offset(90, 62.5),
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                  width: 180, height: 125, child: card(feedback: true)),
            ),
            childWhenDragging: Opacity(
                opacity: 0.35,
                child: _GridDragHandle(color: colors.onSurfaceVariant)),
            child: _GridDragHandle(color: colors.onSurfaceVariant),
          )
        : _buildListDragHandle(dragKey, colors.onSurfaceVariant);
    return _buildListDragTarget(
        scriptName: dragKey, groupId: null, child: card(dragHandle: handle));
  }

  Widget _buildFolderHome(ScriptWorkspaceController controller) {
    final items = controller.homeItems;
    final canDrag = !_multiSelectMode && !_searchMode && !_groupSelectMode;
    Widget buildItem(int index) {
      final item = items[index];
      final group = item.group;
      final draggable = canDrag && !item.isPinned;
      return KeyedSubtree(
        key: ValueKey('home_item_${item.key}'),
        child: group != null
            ? _buildHomeGroupCard(controller, group,
                keyPrefix: 'home_group_reorder',
                grid: _isGridView,
                draggable: draggable)
            : _isGridView
                ? _buildFolderHomeGridScriptCard(item.script!, index,
                    draggable: draggable)
                : _buildFolderHomeScriptListItem(item.script!, index,
                    reorderIndex: draggable ? index : null),
      );
    }

    if (_isGridView) {
      return GridView.builder(
        padding: _browsePadding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: AppBreakpoints.scriptGridColumns(context),
          childAspectRatio: 1.44,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => buildItem(index),
      );
    }

    return ListView.builder(
      itemExtentBuilder: (index, _) => items[index].group != null
          ? _ScriptListPageState._folderListItemExtent
          : _ScriptListPageState._scriptListItemExtent,
      padding: _reorderPadding,
      itemCount: items.length,
      itemBuilder: (context, index) => buildItem(index),
    );
  }

  Widget _buildFolderHomeScriptListItem(dynamic script, int index,
      {required int? reorderIndex}) {
    final snapshot = script as ScriptFile;
    return _ScriptDataScope(
      scriptName: snapshot.name,
      builder: (context, script) {
        final colors = Theme.of(context).colorScheme;
        final displayName = _displayScriptName(script.name, index);
        final selected = _selectedScripts.contains(script.name);
        final canDragScript = reorderIndex != null && !script.isPinned;

        final card = _ScriptCardSurface(
          key: ValueKey('home_script_${script.name}'),
          colors: colors,
          selected: _multiSelectMode && selected,
          pinned: script.isPinned,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _multiSelectMode
                ? setState(() {
                    if (selected) {
                      _selectedScripts.remove(script.name);
                    } else {
                      _selectedScripts.add(script.name);
                    }
                  })
                : _handleScriptTap(script.name),
            onLongPress: () => _multiSelectMode
                ? null
                : _showContextMenu(script.name, script.isPinned,
                    groupId: script.groupId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  if (_multiSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Checkbox(
                        value: selected,
                        onChanged: (_) => setState(() {
                          if (selected) {
                            _selectedScripts.remove(script.name);
                          } else {
                            _selectedScripts.add(script.name);
                          }
                        }),
                      ),
                    )
                  else ...[
                    if (canDragScript)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _buildListDragHandle(
                          script.name,
                          colors.onSurfaceVariant,
                        ),
                      ),
                    _ScriptIcon(
                        colors: colors, size: 44, pinned: script.isPinned),
                  ],
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildMaskedScriptNameText(
                                displayName,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                maxLines: 1,
                              ),
                            ),
                            if (script.isPinned) ...[
                              const SizedBox(width: 6),
                              _PinnedBadge(colors: colors),
                            ],
                          ],
                        ),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _ScriptMetaChip(
                              colors: colors,
                              icon: Icons.schedule_rounded,
                              label: _dateFormat.format(script.modifiedAt),
                            ),
                            _ScriptMetaChip(
                              colors: colors,
                              icon: Icons.play_circle_outline_rounded,
                              label: _formatRunLabel(script.runCount),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!_multiSelectMode) ...[
                    const SizedBox(width: 8),
                    _QuickRunButton(onPressed: () => _runScript(script.name)),
                  ],
                ],
              ),
            ),
          ),
        );

        if (!canDragScript) return card;
        return _buildListDragTarget(
          scriptName: script.name,
          groupId: null,
          child: card,
        );
      },
    );
  }

  Widget _buildFolderHomeGridScriptCard(dynamic script, int index,
      {required bool draggable}) {
    final snapshot = script as ScriptFile;
    return _ScriptDataScope(
      scriptName: snapshot.name,
      builder: (context, script) {
        final selected = _selectedScripts.contains(script.name);

        Widget card({Widget? dragHandle, bool feedback = false}) {
          return _ScriptGridCard(
            key: feedback ? null : ValueKey('home_script_grid_${script.name}'),
            name: _displayScriptName(script.name, index),
            masked: _maskScriptNames,
            modifiedAt: script.modifiedAt,
            runCount: script.runCount,
            dateFormat: _dateFormat,
            pinned: script.isPinned,
            selected: feedback ? null : (_multiSelectMode ? selected : null),
            dragHandle: dragHandle,
            onTap: feedback
                ? () {}
                : () => _multiSelectMode
                    ? setState(() {
                        if (selected) {
                          _selectedScripts.remove(script.name);
                        } else {
                          _selectedScripts.add(script.name);
                        }
                      })
                    : _handleScriptTap(script.name),
            onLongPress: feedback
                ? () {}
                : () => _multiSelectMode
                    ? null
                    : _showContextMenu(script.name, script.isPinned,
                        groupId: script.groupId),
            onRun: feedback || _multiSelectMode
                ? null
                : () => _runScript(script.name),
          );
        }

        if (!draggable) {
          return card();
        }

        final dragHandle = Draggable<String>(
          data: script.name,
          dragAnchorStrategy: (_, __, ___) => const Offset(90, 62.5),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 180,
              height: 125,
              child: card(
                feedback: true,
                dragHandle: _GridDragHandle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _GridDragHandle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          child: _GridDragHandle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );

        return DragTarget<String>(
          key: ValueKey('home_script_grid_target_${script.name}'),
          onWillAcceptWithDetails: (details) {
            return _canAcceptListDrop(details.data, script.name, null);
          },
          onAcceptWithDetails: (details) {
            _commitListDragTarget(details.data, script.name, null);
          },
          builder: (context, candidateData, rejectedData) {
            return AnimatedScale(
              scale: candidateData.isEmpty ? 1 : 0.98,
              duration: const Duration(milliseconds: 120),
              child: card(dragHandle: dragHandle),
            );
          },
        );
      },
    );
  }

  void _beginGridDrag(String scriptName) {
    _gridDraggingScriptName = scriptName;
    _gridDragPreviewTargetName = null;
  }

  void _endGridDrag() {
    if (!mounted) return;
    if (_gridDraggingScriptName == null && _gridDragPreviewTargetName == null) {
      return;
    }
    setState(() {
      _gridDraggingScriptName = null;
      _gridDragPreviewTargetName = null;
    });
  }

  void _previewGridDragTarget(String draggedName, String targetName) {
    if (!mounted || _gridDraggingScriptName != draggedName) return;
    final nextTargetName =
        _canAcceptListDrop(draggedName, targetName, _activeGroupId)
            ? targetName
            : null;
    if (_gridDragPreviewTargetName == nextTargetName) return;

    setState(() {
      _gridDragPreviewTargetName = nextTargetName;
    });
  }

  void _leaveGridDragTarget(String targetName) {
    if (!mounted || _gridDragPreviewTargetName != targetName) return;
    setState(() => _gridDragPreviewTargetName = null);
  }

  void _commitGridDragTarget(String draggedName, String targetName) {
    if (draggedName != targetName) {
      ref
          .read(scriptWorkspaceControllerProvider.notifier)
          .swapScriptPositionsByName(
            draggedName,
            targetName,
            groupId: _activeGroupId,
          );
    }
    _endGridDrag();
  }

  Widget _buildListView(List<dynamic> scripts) {
    final colors = Theme.of(context).colorScheme;
    final canDrag = !_multiSelectMode && !_searchMode;

    Widget buildItem(int index) {
      final script = scripts[index];
      final displayName = _displayScriptName(script.name, index);
      final selected = _selectedScripts.contains(script.name);
      final canDragScript = canDrag && !script.isPinned;
      final card = _ScriptCardSurface(
        key: ValueKey('script_${script.name}'),
        colors: colors,
        selected: _multiSelectMode && selected,
        pinned: script.isPinned,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _multiSelectMode
              ? setState(() {
                  if (selected) {
                    _selectedScripts.remove(script.name);
                  } else {
                    _selectedScripts.add(script.name);
                  }
                })
              : _handleScriptTap(script.name),
          onLongPress: () => _multiSelectMode
              ? null
              : _showContextMenu(script.name, script.isPinned,
                  groupId: script.groupId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                if (_multiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => setState(() {
                        if (selected) {
                          _selectedScripts.remove(script.name);
                        } else {
                          _selectedScripts.add(script.name);
                        }
                      }),
                    ),
                  )
                else ...[
                  if (canDragScript)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _buildListDragHandle(
                        script.name,
                        colors.onSurfaceVariant,
                      ),
                    ),
                  _ScriptIcon(
                      colors: colors, size: 44, pinned: script.isPinned),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildMaskedScriptNameText(
                              displayName,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              maxLines: 1,
                            ),
                          ),
                          if (script.isPinned) ...[
                            const SizedBox(width: 6),
                            _PinnedBadge(colors: colors),
                          ],
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _ScriptMetaChip(
                            colors: colors,
                            icon: Icons.schedule_rounded,
                            label: _dateFormat.format(script.modifiedAt),
                          ),
                          _ScriptMetaChip(
                            colors: colors,
                            icon: Icons.play_circle_outline_rounded,
                            label: _formatRunLabel(script.runCount),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!_multiSelectMode) ...[
                  const SizedBox(width: 8),
                  _QuickRunButton(onPressed: () => _runScript(script.name)),
                ],
              ],
            ),
          ),
        ),
      );

      if (!canDragScript) return card;
      return _buildListDragTarget(
        scriptName: script.name,
        groupId: _activeGroupId,
        child: card,
      );
    }

    if (!canDrag) {
      return ListView.builder(
        itemExtentBuilder: (_, __) =>
            _ScriptListPageState._scriptListItemExtent,
        padding: _reorderPadding,
        itemCount: scripts.length,
        itemBuilder: (context, index) => buildItem(index),
      );
    }

    return ListView.builder(
      itemExtentBuilder: (_, __) => _ScriptListPageState._scriptListItemExtent,
      padding: _reorderPadding,
      itemCount: scripts.length,
      itemBuilder: (context, index) => buildItem(index),
    );
  }

  Widget _buildGridView(List<dynamic> scripts) {
    final canDrag = !_multiSelectMode && !_searchMode;
    final indexByName = <String, int>{};
    for (int i = 0; i < scripts.length; i++) {
      indexByName[scripts[i].name] = i;
    }

    Widget buildStaticGridItem(int index) {
      final script = scripts[index];
      final selected = _selectedScripts.contains(script.name);
      return _ScriptGridCard(
        key: ValueKey('script_grid_static_${script.name}'),
        name: _displayScriptName(script.name, index),
        masked: _maskScriptNames,
        modifiedAt: script.modifiedAt,
        runCount: script.runCount,
        dateFormat: _dateFormat,
        pinned: script.isPinned,
        selected: _multiSelectMode ? selected : null,
        onTap: () => _multiSelectMode
            ? setState(() {
                if (selected) {
                  _selectedScripts.remove(script.name);
                } else {
                  _selectedScripts.add(script.name);
                }
              })
            : _handleScriptTap(script.name),
        onLongPress: () => _multiSelectMode
            ? null
            : _showContextMenu(script.name, script.isPinned,
                groupId: script.groupId),
        onRun: _multiSelectMode ? null : () => _runScript(script.name),
      );
    }

    dynamic previewScriptForSlot(int index) {
      final draggedName = _gridDraggingScriptName;
      final targetName = _gridDragPreviewTargetName;
      if (draggedName == null || targetName == null) return scripts[index];

      final originIndex = indexByName[draggedName];
      final targetIndex = indexByName[targetName];
      if (originIndex == null || targetIndex == null) return scripts[index];

      if (index == originIndex) return scripts[targetIndex];
      if (index == targetIndex) return null;
      return scripts[index];
    }

    Widget buildGridItem(int index) {
      final slotScript = scripts[index];
      final displayScript = previewScriptForSlot(index);
      final selected = displayScript == null
          ? false
          : _selectedScripts.contains(displayScript.name);
      final canDragScript =
          displayScript != null && canDrag && !slotScript.isPinned;
      final targetKey = _gridItemKey(slotScript.name);

      if (displayScript == null) {
        return DragTarget<String>(
          key: ValueKey('script_grid_target_${slotScript.name}'),
          onWillAcceptWithDetails: (details) {
            final draggedName = details.data;
            if (draggedName == slotScript.name) return true;
            final oldIndex = indexByName[draggedName];
            if (oldIndex == null || oldIndex >= scripts.length) return false;
            return !scripts[oldIndex].isPinned && !slotScript.isPinned;
          },
          onMove: (details) {
            _previewGridDragTarget(details.data, slotScript.name);
          },
          onAcceptWithDetails: (details) {
            _commitGridDragTarget(details.data, slotScript.name);
          },
          onLeave: (_) => _leaveGridDragTarget(slotScript.name),
          builder: (context, candidateData, rejectedData) {
            return AnimatedScale(
              scale: candidateData.isEmpty ? 1 : 0.98,
              duration: const Duration(milliseconds: 120),
              child: KeyedSubtree(
                key: targetKey,
                child: _ScriptGridPlaceholder(
                  colors: Theme.of(context).colorScheme,
                ),
              ),
            );
          },
        );
      }

      Widget card({Widget? dragHandle, bool feedback = false}) {
        return _ScriptGridCard(
          key: feedback ? null : ValueKey('script_grid_${slotScript.name}'),
          name: _displayScriptName(displayScript.name, index),
          masked: _maskScriptNames,
          modifiedAt: displayScript.modifiedAt,
          runCount: displayScript.runCount,
          dateFormat: _dateFormat,
          pinned: displayScript.isPinned,
          selected: feedback ? null : (_multiSelectMode ? selected : null),
          dragHandle: dragHandle,
          onTap: feedback
              ? () {}
              : () => _multiSelectMode
                  ? setState(() {
                      if (selected) {
                        _selectedScripts.remove(displayScript.name);
                      } else {
                        _selectedScripts.add(displayScript.name);
                      }
                    })
                  : _handleScriptTap(displayScript.name),
          onLongPress: feedback
              ? () {}
              : () => _multiSelectMode
                  ? null
                  : _showContextMenu(displayScript.name, displayScript.isPinned,
                      groupId: displayScript.groupId),
          onRun: feedback || _multiSelectMode
              ? null
              : () => _runScript(displayScript.name),
        );
      }

      final dragHandle = canDragScript
          ? Draggable<String>(
              key: ValueKey('script_grid_handle_${slotScript.name}'),
              data: slotScript.name,
              maxSimultaneousDrags: _gridDraggingScriptName == null ||
                      _gridDraggingScriptName == slotScript.name
                  ? 1
                  : 0,
              dragAnchorStrategy: (_, __, ___) => const Offset(90, 62.5),
              onDragStarted: () => _beginGridDrag(slotScript.name),
              onDragEnd: (_) => _endGridDrag(),
              onDraggableCanceled: (_, __) => _endGridDrag(),
              onDragCompleted: _endGridDrag,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 180,
                  height: 125,
                  child: card(
                    feedback: true,
                    dragHandle: _GridDragHandle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _GridDragHandle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              child: _GridDragHandle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null;

      return DragTarget<String>(
        key: ValueKey('script_grid_target_${slotScript.name}'),
        onWillAcceptWithDetails: (details) {
          final draggedName = details.data;
          if (draggedName == slotScript.name) return true;
          final oldIndex = indexByName[draggedName];
          if (oldIndex == null || oldIndex >= scripts.length) return false;
          return !scripts[oldIndex].isPinned && !slotScript.isPinned;
        },
        onMove: (details) {
          _previewGridDragTarget(details.data, slotScript.name);
        },
        onAcceptWithDetails: (details) {
          _commitGridDragTarget(details.data, slotScript.name);
        },
        onLeave: (_) => _leaveGridDragTarget(slotScript.name),
        builder: (context, candidateData, rejectedData) {
          return AnimatedScale(
            scale: candidateData.isEmpty ? 1 : 0.98,
            duration: const Duration(milliseconds: 120),
            child: KeyedSubtree(
              key: targetKey,
              child: card(dragHandle: dragHandle),
            ),
          );
        },
      );
    }

    final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: AppBreakpoints.scriptGridColumns(context),
      childAspectRatio: 1.44,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );

    if (!canDrag) {
      return GridView.builder(
        key: _gridViewKey,
        controller: _gridScrollController,
        padding: _browsePadding,
        gridDelegate: gridDelegate,
        itemCount: scripts.length,
        itemBuilder: (context, index) => buildStaticGridItem(index),
      );
    }

    final generatedChildren =
        List.generate(scripts.length, (index) => buildGridItem(index));

    return ReorderableBuilder(
      scrollController: _gridScrollController,
      enableDraggable: false,
      children: generatedChildren,
      builder: (children) {
        return GridView(
          key: _gridViewKey,
          controller: _gridScrollController,
          padding: _browsePadding,
          gridDelegate: gridDelegate,
          children: children,
        );
      },
    );
  }
}
