import 'package:flutter/material.dart';

enum AppThemePalette {
  ocean(
    key: 'ocean',
    label: '海蓝',
    description: '清爽偏理性的默认冷色',
    lightSeed: Color(0xFF2C6BE0),
    darkSeed: Color(0xFF7AA8FF),
  ),
  jade(
    key: 'jade',
    label: '青玉',
    description: '更柔和的青绿色工作台',
    lightSeed: Color(0xFF0E8F72),
    darkSeed: Color(0xFF52C3A5),
  ),
  claude(
    key: 'claude',
    label: 'Claude',
    description: '暖白纸感与低饱和棕调',
    lightSeed: Color(0xFF9E6A43),
    darkSeed: Color(0xFFD2A37C),
  ),
  codex(
    key: 'codex',
    label: 'Codex',
    description: '冷静蓝灰与专业工具感',
    lightSeed: Color(0xFF3D5F85),
    darkSeed: Color(0xFF8EB4DE),
  );

  const AppThemePalette({
    required this.key,
    required this.label,
    required this.description,
    required this.lightSeed,
    required this.darkSeed,
  });

  final String key;
  final String label;
  final String description;
  final Color lightSeed;
  final Color darkSeed;

  static AppThemePalette fromKey(String? key) {
    return AppThemePalette.values.firstWhere(
      (palette) => palette.key == key,
      orElse: () => AppThemePalette.ocean,
    );
  }
}
