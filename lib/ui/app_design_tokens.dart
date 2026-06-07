import 'package:flutter/material.dart';

/// 统一间距常量，基于 4px 网格。
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// 统一圆角常量。
abstract final class AppRadius {
  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const pill = 999.0;

  static BorderRadius circular(double value) => BorderRadius.circular(value);
  static BorderRadius get small => circular(sm);
  static BorderRadius get medium => circular(md);
  static BorderRadius get large => circular(lg);
  static BorderRadius get extraLarge => circular(xl);
  static BorderRadius get pillShape => circular(pill);
}

/// 统一动画时长。
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

/// 统一透明度值。
abstract final class AppOpacity {
  static const border = 0.7;
  static const subtleFill = 0.38;
  static const selectedFill = 0.82;
  static const pinnedFill = 0.72;
}
