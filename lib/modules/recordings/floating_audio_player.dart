import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import 'package:simple_recorder/services/global_player_controller.dart';

/// 全局悬浮挂载点（放进 MaterialApp.builder 的 Stack 末尾）
///
/// 播放器悬浮于所有路由页面之上，跳转页面不中断播放。
/// 非全屏定位，只占自身胶囊区域，其余触摸透过。
class GlobalPlayerOverlay extends StatelessWidget {
  const GlobalPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final c = GlobalPlayerController.instance;
    return Obx(() {
      if (!c.isVisible) return const SizedBox.shrink();
      // 收起态：贴左侧小条（播放键 + 展开键），音乐不停
      if (c.isCollapsed.value) {
        return Positioned(
          left: 0,
          bottom: bottomInset + 16,
          child: const CollapsedPlayerBar(),
        );
      }
      return Positioned(
        left: 0,
        right: 0,
        // 抬高：系统导航条 + 16，为手指拖进度条留操作空间
        bottom: bottomInset + 16,
        // 注意：悬浮层与 Navigator 平级、上方无 Material/Overlay 祖先，
        // 因此内部只允许使用零依赖基础组件（Container/Text/Icon/
        // GestureDetector/CustomPaint/LinearProgressIndicator），
        // 禁止使用 Slider（内部 OverlayPortal 强制要求 Overlay 祖先）。
        child: const FloatingAudioPlayer(),
      );
    });
  }
}

/// 底部避让空白（各页面底部内容在播放器显示时上移，避免被遮挡）
///
/// 用法：放在 Column 尾部 / ListView 底部。
/// 高度 = 播放器顶部位置（bottomInset + 16 + 播放器高约 238 + 间距）。
class PlayerAvoidanceSpace extends StatelessWidget {
  const PlayerAvoidanceSpace({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final c = GlobalPlayerController.instance;
    // 展开态避让播放器（~238px），收起态只避让小条（~48px）
    return Obx(() {
      if (!c.isVisible) return const SizedBox.shrink();
      return SizedBox(
          height: c.isCollapsed.value
              ? bottomInset + 72
              : bottomInset + 262);
    });
  }
}

/// 浮动胶囊式迷你音频播放器（纯展示，状态全在 [GlobalPlayerController]）
///
/// - 正常模式：关闭 / ±10s / 播放暂停 / 文件名 / 剪辑键 + 大进度条
/// - 点击剪辑键进入裁剪模式（针筒选段 / 试听 / 执行裁剪）
class FloatingAudioPlayer extends StatelessWidget {
  const FloatingAudioPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = GlobalPlayerController.instance;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Obx(() => c.isTrimMode.value
          ? _buildTrimMode(theme, c)
          : _buildNormalMode(theme, c)),
    );
  }

  // ── 正常模式 ──

  Widget _buildNormalMode(ThemeData theme, GlobalPlayerController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 第一行：关闭 + 文件名（顶部） ──
        SizedBox(
          height: 32,
          child: Row(
            children: [
              // 关闭
              GestureDetector(
                onTap: c.close,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.close,
                    size: 19,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // 文件名（太长时跑马灯往右滚动）
              Expanded(
                child: Obx(() => _MarqueeText(
                      text: c.currentName.value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    )),
              ),
              // 收起键（贴到屏幕左侧小条，音乐不停）
              GestureDetector(
                onTap: c.toggleCollapse,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.chevron_left,
                    size: 22,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // ── 第二行：播放控制（居中）：上首 / −10s / 播放 / +10s / 下首 ──
        SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上一首
              Obx(() {
                final enabled = c.hasPrev;
                return GestureDetector(
                  onTap: enabled ? c.playPrev : null,
                  child: SizedBox(
                    width: 44,
                    height: 56,
                    child: Icon(
                      Icons.skip_previous,
                      size: 26,
                      color: enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withAlpha(70),
                    ),
                  ),
                );
              }),
              // 后退 10s
              GestureDetector(
                onTap: () => c.seekBySeconds(-10),
                child: const SizedBox(
                  width: 44,
                  height: 56,
                  child: Icon(Icons.replay_10, size: 24),
                ),
              ),
              // 播放/暂停
              StreamBuilder<PlayerState>(
                stream: c.player.playerStateStream,
                builder: (context, stateSnapshot) {
                  final isPlaying = stateSnapshot.data?.playing ?? false;
                  final isLoading = stateSnapshot.data?.processingState ==
                      ProcessingState.loading;
                  return GestureDetector(
                    onTap: isLoading ? null : c.togglePlay,
                    child: Container(
                      width: 52,
                      height: 52,
                      margin:
                          const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isLoading
                            ? Icons.hourglass_top
                            : isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                        size: 28,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  );
                },
              ),
              // 前进 10s
              GestureDetector(
                onTap: () => c.seekBySeconds(10),
                child: const SizedBox(
                  width: 44,
                  height: 56,
                  child: Icon(Icons.forward_10, size: 24),
                ),
              ),
              // 下一首
              Obx(() {
                final enabled = c.hasNext;
                return GestureDetector(
                  onTap: enabled ? c.playNext : null,
                  child: SizedBox(
                    width: 44,
                    height: 56,
                    child: Icon(
                      Icons.skip_next,
                      size: 26,
                      color: enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withAlpha(70),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        // 控制行 ↔ 进度行之间重点拉开间距
        const SizedBox(height: 12),
        // ── 第三行：自绘可拖进度条（加高，手指好拖） ──
        // 不用 Slider：悬浮层无 Overlay 祖先，Slider 内部 OverlayPortal 会报错。
        StreamBuilder<Duration?>(
          stream: c.player.durationStream,
          builder: (context, durSnapshot) {
            final total = durSnapshot.data ?? Duration.zero;
            return StreamBuilder<Duration>(
              stream: c.player.positionStream,
              builder: (context, posSnapshot) {
                final position = posSnapshot.data ?? Duration.zero;
                final progress = total.inMilliseconds > 0
                    ? (position.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;
                return SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Text(
                        GlobalPlayerController.formatDuration(position),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withAlpha(130),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final barW = constraints.maxWidth;
                            void seekTo(double dx) {
                              c.seekRatio(
                                  (dx / barW).clamp(0.0, 1.0));
                            }

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => seekTo(d.localPosition.dx),
                              onHorizontalDragUpdate: (d) =>
                                  seekTo(d.localPosition.dx),
                              child: Container(
                                color: Colors.transparent,
                                child: Center(
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // 轨道底色
                                      Container(
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                      // 已播进度
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(3),
                                        child: Align(
                                          alignment:
                                              Alignment.centerLeft,
                                          widthFactor: progress,
                                          child: Container(
                                            height: 5,
                                            color: theme
                                                .colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      // 拖动手柄
                                      Positioned(
                                        left: (barW * progress - 8)
                                            .clamp(0.0, barW - 16),
                                        top: -5.5,
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withAlpha(40),
                                                blurRadius: 3,
                                                offset:
                                                    const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        GlobalPlayerController.formatDuration(total),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 10),
        // ── 第四行：功能键（剪辑 / 单曲循环 / 自动连播，居中） ──
        SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 剪辑键（进入裁剪模式）
              _buildActionChip(
                theme: theme,
                icon: Icons.content_cut,
                label: '剪辑',
                onTap: c.enterTrimMode,
              ),
              const SizedBox(width: 8),
              // 单曲循环（双态）
              Obx(() => _buildModeChip(
                    theme: theme,
                    icon: Icons.repeat_one,
                    label: '单曲循环',
                    selected: c.loopOne.value,
                    onTap: c.toggleLoopOne,
                  )),
              const SizedBox(width: 8),
              // 自动连播（双态，播完自动下一首）
              Obx(() => _buildModeChip(
                    theme: theme,
                    icon: Icons.playlist_play,
                    label: '自动连播',
                    selected: c.autoPlay.value,
                    onTap: c.toggleAutoPlay,
                  )),
            ],
          ),
        ),
      ],
    );
  }

  // ── 裁剪模式 ──

  Widget _buildTrimMode(ThemeData theme, GlobalPlayerController c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 头部：关闭 + 文件名 + 裁剪徽标 + 完成 ──
        SizedBox(
          height: 40,
          child: Row(
            children: [
              GestureDetector(
                onTap: c.close,
                child: SizedBox(
                  width: 34,
                  height: 40,
                  child: Icon(
                    Icons.close,
                    size: 19,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ),
              Expanded(
                child: Obx(() => _MarqueeText(
                      text: c.currentName.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    )),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '裁剪模式',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 完成裁剪（退出裁剪模式）
              GestureDetector(
                onTap: c.exitTrimMode,
                child: const SizedBox(
                  width: 34,
                  height: 40,
                  child: Icon(Icons.check, size: 21),
                ),
              ),
            ],
          ),
        ),
        // ── 针筒裁剪条 ──
        StreamBuilder<Duration?>(
          stream: c.player.durationStream,
          builder: (context, durSnapshot) {
            final total = durSnapshot.data ?? Duration.zero;
            return _buildTrimSection(theme, c, total);
          },
        ),
      ],
    );
  }

  Widget _buildTrimSection(
      ThemeData theme, GlobalPlayerController c, Duration total) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const syringeW = 34.0; // 针筒宽度
        const trackH = 6.0; // 轨道高度

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 裁剪条区域（针筒 + 轨道） ──
            SizedBox(
              height: 72, // 针筒 48 + 针尖 10 + 间距 2 + 轨道 6 + 底部留白 6
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 轨道背景 + 高亮选中范围
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: trackH,
                        child: Obx(() {
                          final start = c.trimStart.value;
                          final end = c.trimEnd.value;
                          return Row(
                            children: [
                              // 起点前（灰色）
                              if (start > 0.005)
                                Expanded(
                                  flex: (start * 1000).round(),
                                  child: Container(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                              // 选中范围（主色）
                              Expanded(
                                flex: ((end - start) * 1000)
                                    .round()
                                    .clamp(1, 1000),
                                child: Container(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              // 终点后（灰色）
                              if (end < 0.995)
                                Expanded(
                                  flex: ((1.0 - end) * 1000).round(),
                                  child: Container(
                                    color: theme.colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),

                  // 针筒 A（起点）
                  Obx(() {
                    final start = c.trimStart.value;
                    return Positioned(
                      left: totalWidth * start - syringeW / 2,
                      top: 0,
                      child: _buildSyringe(
                        theme: theme,
                        label: GlobalPlayerController.formatDuration(
                          Duration(
                              milliseconds:
                                  (total.inMilliseconds * start).round()),
                        ),
                        isActive: true,
                        totalWidth: totalWidth,
                        onDrag: (dx, totalW) {
                          final end = c.trimEnd.value;
                          final newValue =
                              (totalWidth * start + dx) / totalWidth;
                          c.trimStart.value =
                              newValue.clamp(0.0, end - 0.01);
                        },
                      ),
                    );
                  }),

                  // 针筒 B（终点）
                  Obx(() {
                    final end = c.trimEnd.value;
                    return Positioned(
                      left: totalWidth * end - syringeW / 2,
                      top: 0,
                      child: _buildSyringe(
                        theme: theme,
                        label: GlobalPlayerController.formatDuration(
                          Duration(
                              milliseconds:
                                  (total.inMilliseconds * end).round()),
                        ),
                        isActive: true,
                        totalWidth: totalWidth,
                        onDrag: (dx, totalW) {
                          final start = c.trimStart.value;
                          final newValue = (totalWidth * end + dx) / totalWidth;
                          c.trimEnd.value =
                              newValue.clamp(start + 0.01, 1.0);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 2),

            // ── 起止时间 + 选中时长 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Obx(() {
                final start = c.trimStart.value;
                final end = c.trimEnd.value;
                return Row(
                  children: [
                    // 起点时间
                    Text(
                      GlobalPlayerController.formatDuration(Duration(
                          milliseconds:
                              (total.inMilliseconds * start).round())),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 占用指示
                    Expanded(
                      child: Text(
                        '选中 ${GlobalPlayerController.formatDuration(Duration(milliseconds: (total.inMilliseconds * (end - start)).round()))}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 终点时间
                    Text(
                      GlobalPlayerController.formatDuration(Duration(
                          milliseconds:
                              (total.inMilliseconds * end).round())),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                );
              }),
            ),

            const SizedBox(height: 8),

            // ── 裁剪操作按钮 ──
            Obx(() {
              final isPreviewing = c.isPreviewingTrim.value;
              final isTrimming = c.isTrimming.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 预览选中段
                  _buildActionChip(
                    theme: theme,
                    icon: isPreviewing ? Icons.stop : Icons.play_arrow,
                    label: isPreviewing ? '停止预览' : '试听选中段',
                    onTap: isPreviewing
                        ? c.stopTrimPreview
                        : c.previewTrimSegment,
                  ),
                  const SizedBox(width: 12),
                  // 执行裁剪
                  _buildActionChip(
                    theme: theme,
                    icon: Icons.content_cut,
                    label: isTrimming ? '裁剪中…' : '执行裁剪',
                    onTap: (isTrimming || isPreviewing)
                        ? null
                        : c.executeTrim,
                    isLoading: isTrimming,
                  ),
                ],
              );
            }),

            // ── 裁剪成功提示 ──
            Obx(() {
              if (!c.trimSuccess.value || c.trimmedFileName.value.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '已保存: ${c.trimmedFileName.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  /// 针筒型滑块
  Widget _buildSyringe({
    required ThemeData theme,
    required String label,
    required bool isActive,
    required void Function(double dx, double totalW) onDrag,
    required double totalWidth,
  }) {
    const syringeW = 34.0;
    const syringeH = 48.0;
    final primary = theme.colorScheme.primary;
    final bg = isActive ? primary : theme.colorScheme.surface;
    final fg = isActive ? theme.colorScheme.onPrimary : primary;

    return GestureDetector(
      onPanUpdate: (details) {
        // 水平拖拽，dx 是本次移动距离
        onDrag(details.delta.dx, totalWidth);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 针筒筒体（大圆角矩形） ──
          Container(
            width: syringeW,
            height: syringeH,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primary, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // ── 针头（朝下三角形） ──
          CustomPaint(
            size: const Size(syringeW, 10),
            painter: _TrianglePainter(primary),
          ),
        ],
      ),
    );
  }

  /// 裁剪操作芯片按钮
  Widget _buildActionChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: onTap != null
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              )
            else
              Icon(icon,
                  size: 16, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: onTap != null
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurface.withAlpha(80),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  /// 双态功能芯片（开/关两种视觉状态）
  Widget _buildModeChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final bg = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface.withAlpha(130);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 收起态小条：贴屏幕左侧，仅播放键 + 展开键，音乐不停。
class CollapsedPlayerBar extends StatelessWidget {
  const CollapsedPlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = GlobalPlayerController.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius:
            const BorderRadius.horizontal(right: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(24),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放/暂停
          StreamBuilder<PlayerState>(
            stream: c.player.playerStateStream,
            builder: (context, stateSnapshot) {
              final isPlaying = stateSnapshot.data?.playing ?? false;
              final isLoading = stateSnapshot.data?.processingState ==
                  ProcessingState.loading;
              return GestureDetector(
                onTap: isLoading ? null : c.togglePlay,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLoading
                        ? Icons.hourglass_top
                        : isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                    size: 22,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          // 展开（恢复完整播放器）
          GestureDetector(
            onTap: c.toggleCollapse,
            child: SizedBox(
              width: 32,
              height: 38,
              child: Icon(
                Icons.chevron_right,
                size: 24,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 文件名跑马灯：内容超出可用宽度时自动往右滚动，播完停留后滚回开头循环
///
/// 不溢出时就是普通单行文本。只用 ScrollController + 基础组件，
/// 无 Material/Overlay 祖先依赖，可安全用在全局悬浮层。
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _disposed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScroll());
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // 换歌：旧循环过期退出，回到开头后重新测量启动
      _generation++;
      if (_controller.hasClients) _controller.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScroll());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _maybeScroll() async {
    final gen = ++_generation;
    if (_disposed || !_controller.hasClients) return;
    // 首帧测量：不溢出直接返回
    if (_controller.position.maxScrollExtent <= 0) return;
    while (!_disposed && gen == _generation && _controller.hasClients) {
      // 开头停留 1s，让用户看清文件名开头
      await Future.delayed(const Duration(seconds: 1));
      if (_disposed || gen != _generation || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return;
      // 匀速往右滚动（约 40px/s）
      await _controller.animateTo(
        max,
        duration: Duration(
            milliseconds: (max / 40 * 1000).round().clamp(1000, 8000)),
        curve: Curves.linear,
      );
      if (_disposed || gen != _generation) return;
      // 末尾停留 2s
      await Future.delayed(const Duration(seconds: 2));
      if (_disposed || gen != _generation || !_controller.hasClients) return;
      // 滚回开头
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOut,
      );
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _controller,
      // 禁止手动滑动，只走自动跑马灯，避免与自动滚动打架
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}

/// 朝下三角形绘制（针头）
class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, size.height) // 底部中点（针尖）
      ..lineTo(4, 0) // 左上
      ..lineTo(size.width - 4, 0) // 右上
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
