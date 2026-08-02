import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 迁移护栏：防止已迁移到 Riverpod 的业务模块重新引入 legacy `provider`
/// 依赖或直接读取已删除的 ChangeNotifier。
///
/// 这是 `provider_to_riverpod_migration_plan.md` Level 0 的验收条件之一。
/// 每完成一个模块的迁移，就在 [_migratedModuleRoots] / [_bannedSymbols]
/// 增加对应条目；护栏会在 CI 阶段阻止回退。
void main() {
  /// 已完成 Riverpod 迁移的模块根目录（相对项目根）。
  ///
  /// 这些目录下的源文件不得 `import 'package:provider/provider.dart'`，
  /// 也不得引用对应模块已删除的 legacy ChangeNotifier。
  const migratedModuleRoots = <String>[
    // Level 1 已迁移：
    'lib/features/packages',
    'lib/pages/package_manager_page.dart',
    // Level 2 已迁移（纯 Riverpod application 层，不得引入 legacy provider）：
    'lib/features/scripts/application',
    // 注：script_editor_page / project_file_editor_page 仍用 legacy provider
    // 访问 ExecutionProvider（Level 3），故不列入禁止 legacy import 列表；
    // 但全局禁止 ScriptProvider 符号（见 bannedSymbols）。
  ];

  /// 已迁移模块禁止出现的 legacy 符号（含已删除的 ChangeNotifier 类名）。
  ///
  /// 注意：脚本展示页（script_list_*、script_project_page、run_console_page）
  /// 仍合法使用 legacy provider 访问 ExecutionProvider/ScriptProjectProvider
  /// （Level 3/本地态），故这些文件不加入 migratedModuleRoots，但全局禁止
  /// 已删除的 ScriptProvider 符号。
  const bannedSymbols = <String>[
    // Level 1 已删除的 legacy ChangeNotifier：
    'PackageProvider',
    // Level 2 已删除的 legacy ChangeNotifier：
    'ScriptProvider',
  ];

  test('migrated modules do not import legacy provider package', () {
    for (final root in migratedModuleRoots) {
      final files = Directory(root)
          .existsSync()
          ? Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .toList()
          : [File(root)].where((f) => f.existsSync()).toList();

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains("import 'package:provider/provider.dart'")),
          reason:
              '已迁移模块禁止引入 legacy provider: ${file.path}. 请改用 Riverpod ref.',
        );
      }
    }
  });

  test('migrated modules do not reference banned legacy symbols', () {
    if (bannedSymbols.isEmpty) return;
    for (final root in migratedModuleRoots) {
      final files = Directory(root)
          .existsSync()
          ? Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .toList()
          : [File(root)].where((f) => f.existsSync()).toList();

      for (final file in files) {
        final source = file.readAsStringSync();
        for (final symbol in bannedSymbols) {
          expect(
            source,
            isNot(contains(symbol)),
            reason: '已迁移模块禁止引用 legacy 符号 $symbol: ${file.path}',
          );
        }
      }
    }
  });

  test('package repository interface is defined for Riverpod migration', () {
    // Level 0 交付物：Repository 接口与 fake 必须存在，供后续 Controller 消费。
    final interface =
        File('lib/features/packages/application/package_repository.dart');
    expect(interface.existsSync(), isTrue, reason: '缺少包管理 Repository 接口');
    final source = interface.readAsStringSync();
    expect(source, contains('abstract class PackageRepository'));
    expect(source, contains('class RuntimePackageRepository'));
    expect(source, contains('final packageRepositoryProvider'));
  });

  test('script repository interface is defined for Riverpod migration', () {
    final interface =
        File('lib/features/scripts/application/script_repository.dart');
    expect(interface.existsSync(), isTrue, reason: '缺少脚本 Repository 接口');
    final source = interface.readAsStringSync();
    expect(source, contains('abstract class ScriptRepository'));
    expect(source, contains('class DatabaseScriptRepository'));
    expect(source, contains('final scriptRepositoryProvider'));
  });

  test('execution repository interface is defined for Riverpod migration', () {
    final interface =
        File('lib/features/console/application/execution_repository.dart');
    expect(interface.existsSync(), isTrue, reason: '缺少执行 Repository 接口');
    final source = interface.readAsStringSync();
    expect(source, contains('abstract class ExecutionRepository'));
    expect(source, contains('class RuntimeExecutionRepository'));
    expect(source, contains('final executionRepositoryProvider'));
  });

  test('network inspector repository interface is defined for Riverpod migration', () {
    final interface = File(
      'lib/features/network/application/network_inspector_repository.dart',
    );
    expect(interface.existsSync(), isTrue, reason: '缺少网络检查器 Repository 接口');
    final source = interface.readAsStringSync();
    expect(source,
        contains('abstract class NetworkInspectorRepository'));
    expect(source, contains('class HttpInspectorRepository'));
    expect(source, contains('final networkInspectorRepositoryProvider'));
  });

  test('runtime manager is exposed via Riverpod provider', () {
    final infra = File('lib/providers/infrastructure_providers.dart');
    final source = infra.readAsStringSync();
    expect(source, contains('final runtimeManagerProvider'));
    expect(
      source,
      contains('int invalidateRuntimeBackend(Ref ref)'),
      reason: '需要一个引擎切换失效入口供 Controller 调用',
    );
  });
}
