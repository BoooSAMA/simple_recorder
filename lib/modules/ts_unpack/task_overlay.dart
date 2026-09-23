import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/global_player_controller.dart';
import 'package:simple_recorder/services/unpack_manager.dart';

/// 全局解包/合并任务悬浮窗（挂进 MaterialApp.builder 的 Stack）
///
/// UnpackManager 常驻后台，退出解包页任务不中断；
/// 本悬浮窗让进度在任何页面都可见：点条身跳回解包页，点 X 温和取消。
/// 只用零依赖基础组件（悬浮层无 Material/Overlay 祖先，禁 Slider）。
class GlobalTaskOverlay extends StatelessWidget {
  const GlobalTaskOverlay({super.key});

  // 播放器展开/收起态高度（与 floating_audio_player 对齐，悬浮窗叠在其上方）
  static const double _playerExpandedH = 238;
  static const double _playerCollapsedH = 48;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final m = UnpackManager.instance;
    final p = GlobalPlayerController.instance;
    return Obx(() {
      // 悬浮窗叠在播放器上方，避免重叠
      var bottom = bottomInset + 16.0;
      if (p.isVisible) {
        bottom += (p.isCollapsed.value ? _playerCollapsedH : _playerExpandedH) + 8;
      }
      return Positioned(
        left: 12,
        right: 12,
        bottom: bottom,
        // 显隐淡入淡出（一次性 200ms，平时零开销）
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: m.isProcessing.value
              ? const _TaskBar()
              : const SizedBox.shrink(),
        ),
      );
    });
  }
}

class _TaskBar extends StatelessWidget {
  const _TaskBar();

  void _goUnpack() {
    if (Get.currentRoute != RoutePath.kTsUnpack) {
      Get.toNamed(RoutePath.kTsUnpack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = UnpackManager.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // 条身：点跳回解包页（与取消键是兄弟，无冒泡问题）
          Expanded(
            child: GestureDetector(
              onTap: _goUnpack,
              behavior: HitTestBehavior.opaque,
              child: Obx(() {
                final label =
                    m.taskLabel.value.isEmpty ? "处理" : m.taskLabel.value;
                final idx = m.currentFileIndex.value;
                final total = m.totalFiles.value;
                final title = (total > 0 && idx > 0)
                    ? "$label中 $idx/$total"
                    : "$label中…";
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第一行：任务图标 + 文案 + 百分比
                    Row(
                      children: [
                        Icon(
                          label == "合并"
                              ? Icons.merge
                              : Icons.unarchive_outlined,
                          size: 17,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${(m.progress.value * 100).toStringAsFixed(0)}%",
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 第二行：确定性进度条（无持续动画，80ms 节流驱动，零额外性能）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: m.progress.value,
                        minHeight: 6,
                        backgroundColor: theme
                            .colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 第三行：当前文件名
                    Text(
                      m.currentFileName.value.isEmpty
                          ? "准备中…"
                          : m.currentFileName.value,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withAlpha(130),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(width: 4),
          // 取消键（温和取消：处理完当前文件后停）
          GestureDetector(
            onTap: m.cancelBatch,
            child: SizedBox(
              width: 34,
              height: 44,
              child: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.onSurface.withAlpha(140),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
