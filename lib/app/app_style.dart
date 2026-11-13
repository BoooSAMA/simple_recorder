import 'package:flutter/material.dart';

import 'package:simple_recorder/app/design_tokens.dart';

class AppStyle {
  /// 中文字体回退链。
  ///
  /// 不打包字体文件（会 +10MB 以上），优先命中系统自带的 CJK 字体，
  /// 让中文排版走系统 text stack；英文/数字仍用 Roboto。
  static const List<String> _cjkFallback = [
    'Noto Sans SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'sans-serif',
  ];

  /// 默认种子色（未开启动态取色、也未手动选色时）
  static const Color defaultSeed = Color(0xFF1677FF);

  static ThemeData get lightTheme => buildTheme(Brightness.light);

  static ThemeData get darkTheme => buildTheme(Brightness.dark);

  /// 构建主题。
  ///
  /// [scheme] 来自 dynamic_color 的系统取色（Android 12+）；
  /// 为 null 时用 [seedColor] 生成种子配色。
  static ThemeData buildTheme(
    Brightness brightness, {
    ColorScheme? scheme,
    Color? seedColor,
  }) {
    final colorScheme =
        scheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor ?? defaultSeed,
          brightness: brightness,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
    );

    final textTheme = _textTheme(base.textTheme, colorScheme);
    final divider = colorScheme.outlineVariant.withAlpha(140);

    return base.copyWith(
      textTheme: textTheme,
      dividerColor: divider,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: AppElevation.none,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: AppElevation.card,
        color: colorScheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0.5,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: 13),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: 13),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: colorScheme.outlineVariant),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rSm),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rPill),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rPill),
        side: BorderSide.none,
        backgroundColor: colorScheme.surfaceContainerHigh,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.sm,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withAlpha(200),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearMinHeight: 5,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: AppRadius.rXs,
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
      ),
    );
  }

  /// 中文优先的排版阶梯：行高比 Material 默认更松，字重阶梯更明确。
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    TextStyle? style(
      TextStyle? source,
      double size,
      double height,
      FontWeight weight,
    ) {
      return source?.copyWith(
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: 0,
      );
    }

    return TextTheme(
      displayLarge: style(base.displayLarge, 56, 1.16, FontWeight.w400),
      displayMedium: style(base.displayMedium, 44, 1.18, FontWeight.w400),
      displaySmall: style(base.displaySmall, 36, 1.22, FontWeight.w400),
      headlineLarge: style(base.headlineLarge, 32, 1.25, FontWeight.w600),
      headlineMedium: style(base.headlineMedium, 28, 1.28, FontWeight.w600),
      headlineSmall: style(base.headlineSmall, 24, 1.32, FontWeight.w600),
      titleLarge: style(base.titleLarge, 20, 1.35, FontWeight.w600),
      titleMedium: style(base.titleMedium, 16, 1.4, FontWeight.w600),
      titleSmall: style(base.titleSmall, 14, 1.4, FontWeight.w600),
      bodyLarge: style(base.bodyLarge, 16, 1.5, FontWeight.w400),
      bodyMedium: style(base.bodyMedium, 14, 1.5, FontWeight.w400),
      bodySmall: style(base.bodySmall, 12, 1.45, FontWeight.w400),
      labelLarge: style(base.labelLarge, 14, 1.2, FontWeight.w600),
      labelMedium: style(base.labelMedium, 12, 1.2, FontWeight.w600),
      labelSmall: style(base.labelSmall, 11, 1.2, FontWeight.w500),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontFamilyFallback: _cjkFallback,
    );
  }
}
