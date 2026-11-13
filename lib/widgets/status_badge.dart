import 'package:flutter/material.dart';

import 'package:simple_recorder/app/design_tokens.dart';

/// 语义色调，跨页面保持一致：
/// - success 已解包/完成
/// - warning 录制中
/// - danger  中断/失败
/// - primary 当前播放/强调
/// - neutral 普通计数
enum StatusTone { neutral, primary, success, warning, danger }

/// 小型状态徽章（tonal 底色 + 语义前景色）。
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = StatusTone.neutral});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final foreground = switch (tone) {
      StatusTone.primary => scheme.primary,
      StatusTone.success =>
        dark ? Colors.green.shade300 : Colors.green.shade700,
      StatusTone.warning =>
        dark ? Colors.orange.shade300 : Colors.orange.shade800,
      StatusTone.danger => dark ? Colors.red.shade300 : Colors.red.shade700,
      StatusTone.neutral => scheme.onSurfaceVariant,
    };

    final background = tone == StatusTone.primary
        ? scheme.primary.withAlpha(dark ? 54 : 30)
        : foreground.withAlpha(dark ? 44 : 26);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(color: background, borderRadius: AppRadius.rXs),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: foreground,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
