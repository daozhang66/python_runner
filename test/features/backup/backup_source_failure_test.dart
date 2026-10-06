import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/features/backup/application/backup_state.dart';
import 'package:python_runner/features/backup/presentation/backup_widgets.dart';
import 'package:python_runner/l10n/app_localizations_en.dart';
import 'package:python_runner/l10n/app_localizations_zh.dart';

void main() {
  test('source failures explain missing or changing files in Chinese', () {
    final l = AppLocalizationsZh();
    expect(
      backupFailureMessage(l, const BackupFailure('SOURCE_MISSING')),
      '待备份的脚本或项目文件已不存在。请刷新备份内容，或取消选择缺失的项目后重试。',
    );
    expect(
      backupFailureMessage(l, const BackupFailure('SOURCE_CHANGED')),
      '文件在备份过程中发生变化。请停止编辑或修改文件后重试。',
    );
  });

  test('source failures explain missing or changing files in English', () {
    final l = AppLocalizationsEn();
    expect(
      backupFailureMessage(l, const BackupFailure('SOURCE_MISSING')),
      'A script or project file is missing. Refresh the backup contents or deselect the missing project, then try again.',
    );
    expect(
      backupFailureMessage(l, const BackupFailure('SOURCE_CHANGED')),
      'Files changed during backup. Stop editing or modifying files, then try again.',
    );
  });
}
