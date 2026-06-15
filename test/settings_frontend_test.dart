import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String settingsPageSource() => [
      'lib/pages/settings_page.dart',
      'lib/pages/settings_actions.dart',
      'lib/pages/settings_sections.dart',
      'lib/pages/settings_widgets.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

String themeSettingsPageSource() =>
    File('lib/pages/theme_settings_page.dart').readAsStringSync();

String settingsWidgetsSource() =>
    File('lib/pages/settings_widgets.dart').readAsStringSync();

String runtimeManagerPageSource() =>
    File('lib/pages/runtime_manager_page.dart').readAsStringSync();

void main() {
  test('settings page exposes grouped sections without duplicate runtime card',
      () {
    final source = settingsPageSource();

    expect(source, contains('Widget _buildAppearanceSection('));
    expect(source, contains('Widget _buildRuntimeSection('));
    expect(source, contains('Widget _buildNetworkDebugSection('));
    expect(source, contains('Widget _buildDiagnosticsSection('));
    expect(source, contains('Widget _buildAboutSection('));
    expect(source, contains('_buildAppearanceSection(),'));
    expect(source, contains('_buildRuntimeSection(),'));
    expect(source, contains('_buildNetworkDebugSection(),'));
    expect(source, contains('_buildDiagnosticsSection(),'));
    expect(source, contains('_buildAboutSection(),'));
    expect(source, isNot(contains('_buildRuntimeStatusCard(),')));
    expect(source, isNot(contains('Widget _buildRuntimeStatusCard(')));
    expect(source, isNot(contains('if (false)')));
    expect(source, isNot(contains('ignore: dead_code')));
    expect(source, isNot(contains('=> const SizedBox.shrink()')));
  });

  test('theme custom colors live at the end of more colors card', () {
    final source = themeSettingsPageSource();

    expect(source, contains('class _FluxdoColorsSection'));
    expect(source, contains('customColors: themeState.customColors'));
    expect(source, contains('...customColors.map((color)'));
    expect(source, contains('onAddColor: () => _showColorPicker'));
    expect(source, isNot(contains('class _CustomColorsSection')));
  });

  test('more colors does not duplicate the lilac preset seed', () {
    final source = File('lib/providers/theme_provider.dart').readAsStringSync();
    final classicColors = RegExp(
      r'fluxdoClassicColors = \[([\s\S]*?)\];',
    ).firstMatch(source)!.group(1)!;

    expect(classicColors, isNot(contains('0xFF6750A4')));
    expect(classicColors, contains('Colors.teal'));
    expect(classicColors, isNot(contains('Colors.cyan')));
  });

  test('settings diagnostics keeps log clearing inside app logs page', () {
    final source = settingsPageSource();

    expect(source, contains("title: const Text('应用日志')"));
    expect(source, contains("title: const Text('导出完整日志')"));
    expect(source, isNot(contains("title: const Text('清空系统日志')")));
    expect(source, isNot(contains('Future<void> _clearSystemLogs()')));
  });

  test('user manual reflects current feature behavior', () {
    final source = settingsWidgetsSource();

    expect(source, contains('项目型脚本组'));
    expect(source, contains('设置主程序、运行项目、导入/导出 ZIP'));
    expect(source, contains('终端主题'));
    expect(source, contains('深色、浅色、跟随系统和单色'));
    expect(source, contains('DNS/connect'));
    expect(source, contains('常见网络命令信息'));
    expect(source, contains('requirements.txt 批量安装'));
    expect(source, contains('当前仅 Linux-like 运行引擎支持'));
    expect(source, contains('更多颜色卡片'));
    expect(source, contains('自定义颜色添加到末尾'));
    expect(source, contains('应用日志页可搜索、筛选、导出到剪贴板并清空'));
    expect(source, contains('__pycache__'));
    expect(source, isNot(contains('四套主题色')));
    expect(source, isNot(contains('绿色脉冲')));
    expect(source, isNot(contains('底部红色区域')));
    expect(source, isNot(contains('subprocess 网络命令自动 Hook')));
    expect(source, isNot(contains('开启后悬浮球常驻屏幕')));
    expect(
      source,
      isNot(contains('首页未分组普通脚本可拖拽排序；置顶脚本和文件夹不可拖动')),
    );
    expect(source, isNot(contains('查看、导出或清空运行日志和崩溃日志')));
    expect(source, isNot(contains('直接 import mylib 即可使用，无需额外配置')));
  });

  test('linux-like install screen uses engine wording', () {
    final source = '${settingsPageSource()}\n${runtimeManagerPageSource()}';

    expect(source, contains("title: const Text('管理引擎')"));
    expect(source, contains('安装 Linux-like 运行引擎'));
    expect(source, contains('安装运行引擎'));
    expect(source, contains('修复运行引擎'));
    expect(source, isNot(contains('管理运行时')));
    expect(source, isNot(contains('运行时管理')));
    expect(source, isNot(contains('安装运行时')));
    expect(source, isNot(contains('修复运行时')));
  });
}
