import 'package:flutter/material.dart';

import 'package:simple_recorder/app/design_tokens.dart';

/// 列表行的视觉锚点：圆角方形 tonal 底 + 单色图标。
///
/// 统一用 28px（列表）/ 32px（强调）两种尺寸，避免每行自己写 Container。
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withAlpha(dark ? 40 : 22),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: tint),
    );
  }
}
