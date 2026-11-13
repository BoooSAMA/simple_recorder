import 'package:flutter/material.dart';

/// 全局设计 token。
///
/// 页面里不再散落魔法数字：圆角、间距、动效、阴影统一从这里取，
/// 保证解包页 / 录音页 / 设置页视觉语言一致。
abstract final class AppRadius {
  /// 小徽章、标签
  static const double xs = 6;

  /// 图标容器、输入框
  static const double sm = 8;

  /// 卡片、面板
  static const double md = 12;

  /// 大卡片、底部面板
  static const double lg = 16;

  /// 工具栏 chip
  static const double xl = 20;

  /// 完全圆角（pill / 圆形按钮）
  static const double pill = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));
}

abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppMotion {
  /// 选中态、颜色切换
  static const Duration fast = Duration(milliseconds: 150);

  /// 展开 / 收起、pill 切换
  static const Duration normal = Duration(milliseconds: 220);

  /// 页面级显隐
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutQuint;
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// 表面层级色。
///
/// 动态取色（尤其是壁纸生成的 dark scheme）里 surfaceContainerLow/High
/// 可能和 surface 几乎同色，直接铺上去会让工具条 chip、分组表头"消失"。
/// 这里统一用 onSurface 的低透明度叠加到 surface 上，得到任何主题下
/// 都稳定可见的抬升层级。
abstract final class AppSurface {
  /// 分组表头（最轻）
  static Color header(ColorScheme scheme) => _lift(scheme, 0.05);

  /// 工具条 chip、空状态圆底
  static Color chip(ColorScheme scheme) => _lift(scheme, 0.08);

  /// 底部悬浮 pill（最重）
  static Color floating(ColorScheme scheme) => _lift(scheme, 0.11);

  /// 选中行底色（主色薄涂，仍留在 surface 上）
  static Color selected(ColorScheme scheme) =>
      Color.alphaBlend(scheme.primary.withAlpha(20), scheme.surface);

  /// chip / pill 的细描边，避免纯色块在低对比主题里发闷
  static Color outline(ColorScheme scheme) =>
      scheme.outlineVariant.withAlpha(120);

  static Color _lift(ColorScheme scheme, double level) {
    return Color.alphaBlend(
      scheme.onSurface.withAlpha((255 * level).round()),
      scheme.surface,
    );
  }
}

abstract final class AppElevation {
  static const double none = 0;

  /// 列表卡片默认无阴影，靠 surface 层级区分
  static const double card = 0;

  /// 悬浮工具条
  static const double floating = 6;
}
