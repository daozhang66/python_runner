# 脚本列表拖拽排序功能设计

**日期**: 2026-06-04  
**版本**: v1.0  
**状态**: 待实现

---

## 1. 概述

为 Python Runner 应用的脚本列表添加拖拽排序功能，允许用户通过拖拽操作自定义脚本的显示顺序。支持列表视图和宫格视图两种模式，使用 Flutter 内置的 `ReorderableListView` 实现。

### 目标

- 用户可通过拖拽手柄（⋮⋮ 图标）调整脚本顺序
- 自定义排序顺序持久化保存到 SQLite 数据库
- 置顶脚本始终在最前面，置顶/非置顶区域内部可自由排序
- 搜索模式和多选模式下禁用拖拽

### 非目标

- 不支持跨视图模式的拖拽（列表↔宫格）
- 不支持拖拽到其他页面
- 不实现复杂的自定义拖拽动画（使用 Flutter 内置效果）

---

## 2. 数据模型变更

### ScriptFile 模型

在 `lib/models/script_file.dart` 中增加 `sortOrder` 字段：

```dart
class ScriptFile {
  final String name;
  final String path;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int runCount;
  final bool isPinned;
  final int sortOrder;  // 新增：拖拽排序序号，值越小越靠前

  ScriptFile({
    required this.name,
    required this.path,
    required this.createdAt,
    required this.modifiedAt,
    this.runCount = 0,
    this.isPinned = false,
    this.sortOrder = 0,  // 默认值
  });

  ScriptFile copyWith({
    String? name,
    String? path,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? runCount,
    bool? isPinned,
    int? sortOrder,
  }) {
    return ScriptFile(
      name: name ?? this.name,
      path: path ?? this.path,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      runCount: runCount ?? this.runCount,
      isPinned: isPinned ?? this.isPinned,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'runCount': runCount,
      'isPinned': isPinned ? 1 : 0,
      'sortOrder': sortOrder,
    };
  }

  factory ScriptFile.fromMap(Map<String, dynamic> map) {
    return ScriptFile(
      name: map['name'] as String,
      path: map['path'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch((map['createdAt'] as num).toInt()),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch((map['modifiedAt'] as num).toInt()),
      runCount: map['runCount'] as int? ?? 0,
      isPinned: (map['isPinned'] as int? ?? 0) == 1,
      sortOrder: (map['sortOrder'] as int?) ?? 0,
    );
  }
}
```

---

## 3. 数据库迁移

### DatabaseService 升级

在 `lib/services/database_service.dart` 中将数据库版本从 2 升级到 3：

```dart
// 版本号变更
version: 3,

// 升级逻辑
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE scripts ADD COLUMN isPinned INTEGER DEFAULT 0');
  }
  if (oldVersion < 3) {
    await db.execute('ALTER TABLE scripts ADD COLUMN sortOrder INTEGER DEFAULT 0');
    // 为现有记录分配 sortOrder（按当前顺序）
    await _migrateSortOrder(db);
  }
}
```

### sortOrder 迁移策略

```dart
Future<void> _migrateSortOrder(Database db) async {
  // 获取所有脚本，按当前排序规则（isPinned DESC, modifiedAt DESC）
  final maps = await db.query('scripts', orderBy: 'isPinned DESC, modifiedAt DESC');
  
  // 批量更新 sortOrder
  final batch = db.batch();
  for (int i = 0; i < maps.length; i++) {
    batch.update(
      'scripts',
      {'sortOrder': i},
      where: 'name = ?',
      whereArgs: [maps[i]['name']],
    );
  }
  await batch.commit();
}
```

---

## 4. Provider 层变更

### ScriptProvider 修改

在 `lib/providers/script_provider.dart` 中：

#### 4.1 更新排序逻辑

```dart
void _sortScripts() {
  _scripts.sort((a, b) {
    // 置顶脚本始终在最前面
    final pinCompare = (b.isPinned ? 1 : 0).compareTo(a.isPinned ? 1 : 0);
    if (pinCompare != 0) return pinCompare;
    // 同一区域内按 sortOrder 排序（值越小越靠前）
    return a.sortOrder.compareTo(b.sortOrder);
  });
}
```

#### 4.2 新增 reorderScript 方法

```dart
Future<void> reorderScript(String name, int newIndex) async {
  // 1. 找到当前脚本索引
  final oldIndex = _scripts.indexWhere((s) => s.name == name);
  if (oldIndex < 0) return;
  
  // 2. 检查移动是否合法（置顶/非置顶不能跨区域移动）
  final isPinned = _scripts[oldIndex].isPinned;
  final pinnedCount = _scripts.where((s) => s.isPinned).length;
  
  // 确保 newIndex 在合法范围内
  if (isPinned && newIndex >= pinnedCount) return;
  if (!isPinned && newIndex < pinnedCount) return;
  
  // 3. 从列表中移除并插入到新位置
  final script = _scripts.removeAt(oldIndex);
  _scripts.insert(newIndex, script);
  
  // 4. 重新分配所有脚本的 sortOrder
  for (int i = 0; i < _scripts.length; i++) {
    _scripts[i] = _scripts[i].copyWith(sortOrder: i);
  }
  
  // 5. 批量更新数据库
  await _db.batchUpdateSortOrders(_scripts);
  
  notifyListeners();
}
```

#### 4.3 新建脚本时的 sortOrder

```dart
Future<bool> createScript(String name, {String content = ''}) async {
  // ...现有逻辑...
  
  // 设置新脚本的 sortOrder 为当前最大值 + 1
  final maxOrder = _scripts.fold<int>(0, (max, s) => s.sortOrder > max ? s.sortOrder : max);
  final script = ScriptFile(
    name: name,
    path: path,
    createdAt: now,
    modifiedAt: now,
    sortOrder: maxOrder + 1,  // 排在最后
  );
  
  // ...后续逻辑...
}
```

---

## 5. UI 层变更

### 5.1 列表视图变更

在 `lib/pages/script_list_page.dart` 的 `_buildListView` 方法中：

```dart
Widget _buildListView(List<dynamic> scripts) {
  final colors = Theme.of(context).colorScheme;
  final provider = context.read<ScriptProvider>();
  
  return ReorderableListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 4),
    itemCount: scripts.length,
    onReorder: (oldIndex, newIndex) {
      // 处理 ReorderableListView 的索引调整
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      provider.reorderScript(scripts[oldIndex].name, newIndex);
    },
    itemBuilder: (context, index) {
      final script = scripts[index];
      final displayName = script.name.replaceAll('.py', '');
      final selected = _selectedScripts.contains(script.name);
      
      return TweenAnimationBuilder<double>(
        key: ValueKey('script_${script.name}'),
        // ...现有动画逻辑...
        child: _ScriptCardSurface(
          // ...现有卡片样式...
          child: InkWell(
            // ...现有点击逻辑...
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  // 拖拽手柄（仅在非多选、非搜索模式下显示）
                  if (!_multiSelectMode && !_searchMode)
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 24,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // ...现有内容（checkbox/图标、文字、运行按钮）...
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
```

### 5.2 宫格视图变更

在 `_buildGridView` 方法中：

```dart
Widget _buildGridView(List<dynamic> scripts) {
  final provider = context.read<ScriptProvider>();
  
  return ReorderableListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
    itemCount: scripts.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      childAspectRatio: 1.44,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    onReorder: (oldIndex, newIndex) {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      provider.reorderScript(scripts[oldIndex].name, newIndex);
    },
    itemBuilder: (context, index) {
      final script = scripts[index];
      final selected = _selectedScripts.contains(script.name);
      
      return _ScriptGridCard(
        key: ValueKey('script_grid_${script.name}'),
        // ...现有属性...
        dragHandle: !_multiSelectMode && !_searchMode
            ? ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
              )
            : null,
      );
    },
  );
}
```

### 5.3 宫格卡片组件修改

在 `_ScriptGridCard` 组件中添加 `dragHandle` 属性：

```dart
class _ScriptGridCard extends StatelessWidget {
  // ...现有属性...
  final Widget? dragHandle;  // 新增

  const _ScriptGridCard({
    // ...现有参数...
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return _ScriptCardSurface(
      // ...现有样式...
      child: InkWell(
        // ...现有逻辑...
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ScriptIcon(colors: colors, size: 36, fontSize: 13),
                  const Spacer(),
                  // 拖拽手柄（如果有）
                  if (dragHandle != null) dragHandle!,
                  // ...其他现有元素...
                ],
              ),
              // ...现有内容...
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 6. 边界情况处理

### 6.1 置顶脚本拖拽限制

- 置顶脚本只能在置顶区域内拖拽
- 非置顶脚本只能在非置顶区域内拖拽
- 在 `reorderScript` 方法中验证移动合法性

### 6.2 模式切换禁用拖拽

- 搜索模式（`_searchMode = true`）：不显示拖拽手柄，禁用 `ReorderableListView`
- 多选模式（`_multiSelectMode = true`）：不显示拖拽手柄，禁用 `ReorderableListView`
- 实现方式：条件判断是否使用 `ReorderableListView` 或普通 `ListView`

### 6.3 空列表和单元素列表

- 空列表：无需处理，`ReorderableListView` 自动处理
- 单元素列表：拖拽手柄仍显示，但拖拽无实际效果（用户体验一致）

### 6.4 动画效果

使用 Flutter `ReorderableListView` 内置动画：
- 拖拽开始：卡片添加阴影，轻微放大
- 拖拽中：其他卡片自动让位
- 拖拽结束：平滑过渡到新位置
- 无需自定义 `AnimationController`

---

## 7. 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `lib/models/script_file.dart` | 修改 | 增加 `sortOrder` 字段 |
| `lib/services/database_service.dart` | 修改 | 数据库版本升级、迁移逻辑、批量更新方法 |
| `lib/providers/script_provider.dart` | 修改 | 更新排序逻辑、新增 `reorderScript` 方法 |
| `lib/pages/script_list_page.dart` | 修改 | 替换为 `ReorderableListView`、添加拖拽手柄 |

---

## 8. 测试要点

### 单元测试
- `ScriptFile.fromMap` / `toMap` 正确处理 `sortOrder`
- `_sortScripts` 排序逻辑验证
- `reorderScript` 边界情况（置顶限制、索引越界）

### 集成测试
- 数据库版本迁移（v2 → v3）
- 拖拽排序后重启 app 验证顺序保持
- 置顶/取消置顶后拖拽限制正确

### UI 测试
- 列表视图拖拽手柄显示/隐藏
- 宫格视图拖拽手柄显示/隐藏
- 搜索/多选模式下拖拽禁用
- 拖拽动画流畅性

---

## 9. 实施步骤

1. **数据层**：修改 `ScriptFile` 模型，添加 `sortOrder` 字段
2. **数据库**：升级 `DatabaseService`，实现迁移逻辑
3. **Provider**：更新 `ScriptProvider`，添加 `reorderScript` 方法
4. **UI - 列表视图**：替换为 `ReorderableListView`，添加拖拽手柄
5. **UI - 宫格视图**：替换为 `ReorderableListView`，修改卡片组件
6. **测试**：编写单元测试和集成测试
7. **优化**：处理边界情况，优化动画效果

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 数据库迁移失败 | 数据丢失 | 迁移前备份，使用事务处理 |
| 拖拽性能问题 | 卡顿 | 使用 `const` 构造函数优化重建 |
| 置顶逻辑冲突 | 排序错乱 | 严格验证移动合法性 |
| ReorderableListView 兼容性 | 功能异常 | 测试 Flutter 版本兼容性 |

---

## 附录：技术参考

- [Flutter ReorderableListView 文档](https://api.flutter.dev/flutter/material/ReorderableListView-class.html)
- [Flutter ReorderableListView.gridDelegate](https://api.flutter.dev/flutter/material/ReorderableListView/gridDelegate.html)
- [SQLite ALTER TABLE 文档](https://www.sqlite.org/lang_altertable.html)
