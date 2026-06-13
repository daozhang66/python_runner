// ignore_for_file: invalid_use_of_protected_member

part of 'script_list_page.dart';

extension _ScriptListContent on _ScriptListPageState {
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
        '匹配 $visibleCount / 共 $totalCount 个',
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
    );
  }

  DateTime _homeRecentTime(dynamic item) {
    if (item is ScriptGroup) return item.modifiedAt;
    return item.modifiedAt as DateTime;
  }

  int _homeRecentSortOrder(dynamic item) {
    if (item is ScriptGroup) return item.sortOrder;
    return item.sortOrder as int;
  }

  int _compareHomeRecentItems(dynamic a, dynamic b) {
    final timeCompare = _homeRecentTime(b).compareTo(_homeRecentTime(a));
    if (timeCompare != 0) return timeCompare;
    return _homeRecentSortOrder(a).compareTo(_homeRecentSortOrder(b));
  }

  double _homeItemExtent(dynamic item) {
    return item is ScriptGroup
        ? _ScriptListPageState._folderListItemExtent
        : _ScriptListPageState._scriptListItemExtent;
  }

  Widget _buildHomeGroupCard(
    ScriptProvider provider,
    ScriptGroup group, {
    required String keyPrefix,
    required bool grid,
  }) {
    final selected = group.id != null && _selectedGroupIds.contains(group.id);
    return _ScriptFolderCard(
      key: ValueKey('${keyPrefix}_${group.id}'),
      name: _displayGroupName(group.name),
      masked: _maskScriptNames,
      count: group.id == null ? 0 : provider.scriptCountInGroup(group.id!),
      isProject: group.isProject,
      hasMainFile: group.mainFilePath != null,
      grid: grid,
      selected: _groupSelectMode ? selected : null,
      onTap: _groupSelectMode
          ? () => _toggleGroupSelection(group)
          : (_multiSelectMode ? null : () => _openGroup(group)),
      onLongPress: _multiSelectMode
          ? null
          : (_groupSelectMode ? null : () => _showGroupContextMenu(group)),
    );
  }

  Widget _buildHomeRecentGridItem(
    ScriptProvider provider,
    dynamic item,
    int index,
  ) {
    if (item is ScriptGroup) {
      return _buildHomeGroupCard(
        provider,
        item,
        keyPrefix: 'home_project_grid',
        grid: true,
      );
    }
    return _buildFolderHomeGridScriptCard(
      item,
      index,
      draggable: !_multiSelectMode && !_searchMode,
    );
  }

  Widget _buildHomeRecentListItem(
    ScriptProvider provider,
    dynamic item,
    int index, {
    required int? reorderIndex,
    required String keyPrefix,
  }) {
    if (item is ScriptGroup) {
      return _buildHomeGroupCard(
        provider,
        item,
        keyPrefix: keyPrefix,
        grid: false,
      );
    }
    return _buildFolderHomeScriptListItem(
      item,
      index,
      reorderIndex: reorderIndex,
    );
  }

  Widget _buildFolderHome(ScriptProvider provider, List<dynamic> scripts) {
    final regularGroups =
        provider.groups.where((group) => !group.isProject).toList();
    final projectGroups =
        provider.groups.where((group) => group.isProject).toList();
    final visibleScripts =
        scripts.where((script) => script.groupId == null).toList();
    final pinnedScripts =
        visibleScripts.where((script) => script.isPinned).toList();
    final regularScripts =
        visibleScripts.where((script) => !script.isPinned).toList();
    final recentItems = <dynamic>[...regularScripts, ...projectGroups]
      ..sort(_compareHomeRecentItems);
    final firstFolderIndex = pinnedScripts.length;
    final firstRecentIndex = pinnedScripts.length + regularGroups.length;
    final itemCount = firstRecentIndex + recentItems.length;

    if (_isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.44,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index < firstFolderIndex) {
            final script = pinnedScripts[index];
            return _buildFolderHomeGridScriptCard(
              script,
              index,
              draggable: false,
            );
          }

          if (index < firstRecentIndex) {
            return _buildHomeGroupCard(
              provider,
              regularGroups[index - firstFolderIndex],
              keyPrefix: 'home_group_grid',
              grid: true,
            );
          }

          return _buildHomeRecentGridItem(
            provider,
            recentItems[index - firstRecentIndex],
            index - regularGroups.length,
          );
        },
      );
    }

    final canDrag = !_multiSelectMode && !_searchMode;
    if (!canDrag) {
      return ListView.builder(
        itemExtentBuilder: (index, _) {
          if (index < firstFolderIndex) {
            return _ScriptListPageState._scriptListItemExtent;
          }
          if (index < firstRecentIndex) {
            return _ScriptListPageState._folderListItemExtent;
          }
          return _homeItemExtent(recentItems[index - firstRecentIndex]);
        },
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index < firstFolderIndex) {
            return _buildFolderHomeScriptListItem(
              pinnedScripts[index],
              index,
              reorderIndex: null,
            );
          }

          if (index < firstRecentIndex) {
            return _buildHomeGroupCard(
              provider,
              regularGroups[index - firstFolderIndex],
              keyPrefix: 'home_group_list',
              grid: false,
            );
          }

          return _buildHomeRecentListItem(
            provider,
            recentItems[index - firstRecentIndex],
            index - regularGroups.length,
            reorderIndex: null,
            keyPrefix: 'home_project_list',
          );
        },
      );
    }

    return ListView.builder(
      itemExtentBuilder: (index, _) {
        if (index < firstFolderIndex) {
          return _ScriptListPageState._scriptListItemExtent;
        }
        if (index < firstRecentIndex) {
          return _ScriptListPageState._folderListItemExtent;
        }
        return _homeItemExtent(recentItems[index - firstRecentIndex]);
      },
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < firstFolderIndex) {
          return _buildFolderHomeScriptListItem(
            pinnedScripts[index],
            index,
            reorderIndex: null,
          );
        }

        if (index < firstRecentIndex) {
          return _buildHomeGroupCard(
            provider,
            regularGroups[index - firstFolderIndex],
            keyPrefix: 'home_group_reorder',
            grid: false,
          );
        }

        return _buildHomeRecentListItem(
          provider,
          recentItems[index - firstRecentIndex],
          index - regularGroups.length,
          reorderIndex: recentItems[index - firstRecentIndex] is ScriptGroup
              ? null
              : index,
          keyPrefix: 'home_project_reorder',
        );
      },
    );
  }

  Widget _buildFolderHomeScriptListItem(dynamic script, int index,
      {required int? reorderIndex}) {
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
            : _openEditor(script.name),
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
                _ScriptIcon(colors: colors, size: 44),
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
  }

  Widget _buildFolderHomeGridScriptCard(dynamic script, int index,
      {required bool draggable}) {
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
                : _openEditor(script.name),
        onLongPress: feedback
            ? () {}
            : () => _multiSelectMode
                ? null
                : _showContextMenu(script.name, script.isPinned,
                    groupId: script.groupId),
        onRun:
            feedback || _multiSelectMode ? null : () => _runScript(script.name),
      );
    }

    if (!draggable) {
      return card();
    }

    final dragHandle = Draggable<String>(
      data: script.name,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedbackOffset: const Offset(90, 62.5),
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
        final draggedName = details.data;
        if (draggedName == script.name) return true;
        final dragged = context
            .read<ScriptProvider>()
            .ungroupedScripts
            .where((s) => s.name == draggedName)
            .cast<dynamic>()
            .toList();
        return dragged.isNotEmpty && dragged.first.isPinned == false;
      },
      onAcceptWithDetails: (details) {
        if (details.data == script.name) return;
        context.read<ScriptProvider>().swapScriptPositionsByName(
              details.data,
              script.name,
              groupId: null,
            );
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedScale(
          scale: candidateData.isEmpty ? 1 : 0.98,
          duration: const Duration(milliseconds: 120),
          child: card(dragHandle: dragHandle),
        );
      },
    );
  }

  void _beginGridDrag(String scriptName) {
    _gridDraggingScriptName = scriptName;
    _gridDragPreviewTargetName = null;
  }

  void _endGridDrag() {
    if (_gridDraggingScriptName == null && _gridDragPreviewTargetName == null) {
      return;
    }
    setState(() {
      _gridDraggingScriptName = null;
      _gridDragPreviewTargetName = null;
    });
  }

  void _previewGridDragTarget(String draggedName, String targetName) {
    if (_gridDraggingScriptName != draggedName) return;
    final nextTargetName = draggedName == targetName ? null : targetName;
    if (_gridDragPreviewTargetName == nextTargetName) return;

    setState(() {
      _gridDragPreviewTargetName = nextTargetName;
    });
  }

  void _commitGridDragTarget(String draggedName, String targetName) {
    if (draggedName != targetName) {
      context.read<ScriptProvider>().swapScriptPositionsByName(
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
              : _openEditor(script.name),
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
                  _ScriptIcon(colors: colors, size: 44),
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
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: scripts.length,
        itemBuilder: (context, index) => buildItem(index),
      );
    }

    return ListView.builder(
      itemExtentBuilder: (_, __) => _ScriptListPageState._scriptListItemExtent,
      padding: const EdgeInsets.symmetric(vertical: 4),
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
            : _openEditor(script.name),
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
      final canDragScript = displayScript != null &&
          _gridDraggingScriptName == null &&
          canDrag &&
          !displayScript.isPinned;
      final targetKey = GlobalKey();

      if (displayScript == null) {
        return DragTarget<String>(
          key: ValueKey('script_grid_placeholder_${slotScript.name}'),
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
          builder: (context, candidateData, rejectedData) {
            return KeyedSubtree(
              key: targetKey,
              child: _ScriptGridPlaceholder(
                colors: Theme.of(context).colorScheme,
              ),
            );
          },
        );
      }

      Widget card({Widget? dragHandle, bool feedback = false}) {
        return _ScriptGridCard(
          key: feedback ? null : ValueKey('script_grid_${displayScript.name}'),
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
                  : _openEditor(displayScript.name),
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
              data: displayScript.name,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedbackOffset: const Offset(90, 62.5),
              onDragStarted: () => _beginGridDrag(displayScript.name),
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
        key: ValueKey('script_grid_target_${displayScript.name}'),
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

    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 1.44,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    );

    if (!canDrag) {
      return GridView.builder(
        key: _gridViewKey,
        controller: _gridScrollController,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
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
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          gridDelegate: gridDelegate,
          children: children,
        );
      },
    );
  }
}
