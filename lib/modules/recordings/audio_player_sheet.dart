import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

/// 底部弹出音频播放器（支持裁剪模式）
///
/// 调用方式：
/// ```dart
/// ShowAudioPlayerSheet.show(context, filePath: '/path/to/file.m4a', fileName: 'xxx.m4a');
/// ```
class ShowAudioPlayerSheet {
  static void show(
    BuildContext context, {
    required String filePath,
    required String fileName,
  }) {
    Get.bottomSheet(
      AudioPlayerSheetContent(filePath: filePath, fileName: fileName),
      isScrollControlled: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    );
  }
}

class AudioPlayerSheetContent extends StatefulWidget {
  final String filePath;
  final String fileName;

  const AudioPlayerSheetContent({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<AudioPlayerSheetContent> createState() =>
      _AudioPlayerSheetContentState();
}

class _AudioPlayerSheetContentState extends State<AudioPlayerSheetContent> {
  late final AudioPlayer _player;
  bool _hasError = false;

  // ── 裁剪模式状态 ──
  bool _isTrimMode = false;
  double _trimStart = 0.0; // 0.0 ~ 1.0
  double _trimEnd = 1.0;
  bool _isPreviewingTrim = false;
  bool _isTrimming = false;
  bool _trimSuccess = false;
  String? _trimmedFilePath;
  StreamSubscription<Duration>? _previewSub;

  String _originalAudioSourcePath = '';

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _originalAudioSourcePath = widget.filePath;
      await _player.setAudioSource(
        AudioSource.file(widget.filePath),
        preload: true,
      );
      // 自动开始播放
      await _player.play();
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    _previewSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── 时间格式化 ──

  String _formatDuration(Duration d) {
    if (d.inSeconds >= 3600) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// FFmpeg 用的时间格式 HH:MM:SS
  String _formatDurationFfmpeg(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 根据 0.0~1.0 值获取 Duration
  Duration _valueToDuration(double value, Duration total) {
    return Duration(
      milliseconds: (total.inMilliseconds * value).round(),
    );
  }

  // ── 裁剪模式切换 ──

  void _toggleTrimMode() {
    if (_isTrimMode) {
      // 退出裁剪模式
      _exitTrimMode();
    } else {
      // 进入裁剪模式
      setState(() {
        _isTrimMode = true;
        _trimStart = 0.0;
        _trimEnd = 1.0;
        _isPreviewingTrim = false;
        _trimSuccess = false;
        _trimmedFilePath = null;
      });
      _player.pause();
    }
  }

  Future<void> _exitTrimMode() async {
    await _previewSub?.cancel();
    _previewSub = null;
    await _player.stop();
    setState(() {
      _isTrimMode = false;
      _isPreviewingTrim = false;
    });
  }

  // ── 裁剪预览 ──

  Future<void> _previewTrimSegment() async {
    final duration = _player.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;

    final startMs = (duration.inMilliseconds * _trimStart).round();
    final endMs = (duration.inMilliseconds * _trimEnd).round();
    if (endMs - startMs < 500) return;

    setState(() => _isPreviewingTrim = true);

    // 取消旧订阅
    await _previewSub?.cancel();

    // 跳转到起始位置播放
    await _player.seek(Duration(milliseconds: startMs));
    await _player.play();

    // 监听位置，到达终点时自动暂停
    _previewSub = _player.positionStream.listen((pos) {
      if (pos.inMilliseconds >= endMs) {
        _player.pause();
        _previewSub?.cancel();
      }
    });
  }

  Future<void> _stopTrimPreview() async {
    await _previewSub?.cancel();
    _previewSub = null;
    await _player.stop();
    setState(() => _isPreviewingTrim = false);
  }

  // ── 执行裁剪 ──

  Future<void> _executeTrim() async {
    final total = _player.duration;
    if (total == null || total.inMilliseconds <= 0) return;

    final startMs = (total.inMilliseconds * _trimStart).round();
    final endMs = (total.inMilliseconds * _trimEnd).round();
    if (endMs - startMs < 1000) {
      Get.snackbar('提示', '选中片段太短（至少 1 秒）');
      return;
    }

    setState(() => _isTrimming = true);

    final inputPath = _originalAudioSourcePath;
    final baseName = inputPath.replaceAll('.m4a', '');
    var outputPath = '${baseName}_trimmed.m4a';

    // 避免覆盖
    int counter = 1;
    while (File(outputPath).existsSync()) {
      outputPath = '${baseName}_trimmed($counter).m4a';
      counter++;
    }

    final startStr = _formatDurationFfmpeg(Duration(milliseconds: startMs));
    final endStr = _formatDurationFfmpeg(Duration(milliseconds: endMs));

    // FFmpeg: -ss start -to end -c:a copy（不重编码）
    final args = [
      '-y',
      '-i',
      inputPath,
      '-ss',
      startStr,
      '-to',
      endStr,
      '-c:a',
      'copy',
      '-vn',
      outputPath,
    ];

    final completer = Completer<void>();
    await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        setState(() {
          _trimSuccess = true;
          _trimmedFilePath = outputPath;
        });
        Get.snackbar('裁剪成功', outputPath.split('/').last);
      } else {
        setState(() {
          _trimSuccess = false;
          _trimmedFilePath = null;
        });
        Get.snackbar('裁剪失败', '请检查文件是否损坏');
      }
      completer.complete();
    });
    await completer.future;

    setState(() => _isTrimming = false);
  }

  // ── 播放控制 ──

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  // ── 构建 UI ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖动把手 ──
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (_hasError)
            _buildErrorState(theme)
          else ...[
            // ── 文件名 + 裁剪模式指示 ──
            _buildHeader(theme),

            // ── 进度条 / 裁剪条 ──
            StreamBuilder<Duration?>(
              stream: _player.durationStream,
              builder: (context, durSnapshot) {
                final total = durSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, posSnapshot) {
                    final position = posSnapshot.data ?? Duration.zero;
                    final progress = total.inMilliseconds > 0
                        ? (position.inMilliseconds / total.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;

                    if (_isTrimMode) {
                      return _buildTrimSection(theme, total);
                    }
                    return _buildProgressSection(theme, total, progress);
                  },
                );
              },
            ),

            const SizedBox(height: 4),

            // ── 底部控制栏 ──
            if (_isTrimMode)
              _buildTrimControls(theme)
            else
              _buildNormalControls(theme),
          ],
        ],
      ),
    );
  }

  // ── 错误状态 ──

  Widget _buildErrorState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: 8),
          Text(
            '无法播放此文件',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ── 头部：文件名 + 裁剪模式指示 ──

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.fileName,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_isTrimMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        ],
      ),
    );
  }

  // ── 正常模式：进度条 ──

  Widget _buildProgressSection(
      ThemeData theme, Duration total, double progress) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 4,
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: progress,
            onChanged: (v) {
              final seekPos = Duration(
                milliseconds: (total.inMilliseconds * v).round(),
              );
              _player.seek(seekPos);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(
                  _valueToDuration(progress, total),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
              Text(
                _formatDuration(total),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 裁剪模式：裁剪条 ──

  Widget _buildTrimSection(ThemeData theme, Duration total) {
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
                        child: Row(
                          children: [
                            // 起点前（灰色）
                            if (_trimStart > 0.005)
                              Expanded(
                                flex: (_trimStart * 1000).round(),
                                child: Container(
                                  color: theme.colorScheme
                                      .surfaceContainerHighest,
                                ),
                              ),
                            // 选中范围（主色）
                            Expanded(
                              flex: ((_trimEnd - _trimStart) * 1000)
                                  .round()
                                  .clamp(1, 1000),
                              child: Container(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            // 终点后（灰色）
                            if (_trimEnd < 0.995)
                              Expanded(
                                flex: ((1.0 - _trimEnd) * 1000).round(),
                                child: Container(
                                  color: theme.colorScheme
                                      .surfaceContainerHighest,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 针筒 A（起点）
                  Positioned(
                    left: totalWidth * _trimStart - syringeW / 2,
                    top: 0,
                    child: _buildSyringe(
                      theme: theme,
                      label: _formatDuration(
                        _valueToDuration(_trimStart, total),
                      ),
                      isActive: true,
                      onDrag: (dx, totalW) {
                        setState(() {
                          final newValue =
                              (totalWidth * _trimStart + dx) / totalWidth;
                          _trimStart = newValue.clamp(0.0, _trimEnd - 0.01);
                        });
                      },
                      totalWidth: totalWidth,
                    ),
                  ),

                  // 针筒 B（终点）
                  Positioned(
                    left: totalWidth * _trimEnd - syringeW / 2,
                    top: 0,
                    child: _buildSyringe(
                      theme: theme,
                      label: _formatDuration(
                        _valueToDuration(_trimEnd, total),
                      ),
                      isActive: true,
                      onDrag: (dx, totalW) {
                        setState(() {
                          final newValue =
                              (totalWidth * _trimEnd + dx) / totalWidth;
                          _trimEnd = newValue.clamp(_trimStart + 0.01, 1.0);
                        });
                      },
                      totalWidth: totalWidth,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 2),

            // ── 起止时间 + 总时长 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  // 起点时间
                  Text(
                    _formatDuration(_valueToDuration(_trimStart, total)),
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
                      '选中 ${_formatDuration(_valueToDuration(_trimEnd - _trimStart, total))}',
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
                    _formatDuration(_valueToDuration(_trimEnd, total)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── 裁剪操作按钮 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 预览选中段
                _buildActionChip(
                  theme: theme,
                  icon: _isPreviewingTrim ? Icons.stop : Icons.play_arrow,
                  label: _isPreviewingTrim ? '停止预览' : '试听选中段',
                  onTap: _isPreviewingTrim
                      ? _stopTrimPreview
                      : _previewTrimSegment,
                ),
                const SizedBox(width: 12),
                // 执行裁剪
                _buildActionChip(
                  theme: theme,
                  icon: Icons.content_cut,
                  label: _isTrimming ? '裁剪中…' : '执行裁剪',
                  onTap: (_isTrimming || _isPreviewingTrim) ? null : _executeTrim,
                  isLoading: _isTrimming,
                ),
              ],
            ),

            // ── 裁剪成功提示 ──
            if (_trimSuccess && _trimmedFilePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 12, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '已保存: ${_trimmedFilePath!.split('/').last}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
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
              Icon(icon, size: 16, color: theme.colorScheme.onSecondaryContainer),
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

  // ── 正常模式：底部控制栏 ──

  Widget _buildNormalControls(ThemeData theme) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, stateSnapshot) {
        final isPlaying = stateSnapshot.data?.playing ?? false;
        final isLoading = stateSnapshot.data?.processingState ==
            ProcessingState.loading;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 关闭
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Get.back(),
                tooltip: '关闭',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),

            const SizedBox(width: 16),

            // 播放/暂停
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filled(
                icon: Icon(
                  isLoading
                      ? Icons.hourglass_top
                      : isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                  size: 28,
                ),
                onPressed: isLoading ? null : () => _togglePlay(),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ),

            const SizedBox(width: 16),

            // 裁剪入口
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.content_cut, size: 20),
                onPressed: _toggleTrimMode,
                tooltip: '裁剪',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── 裁剪模式：底部控制栏 ──

  Widget _buildTrimControls(ThemeData theme) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, stateSnapshot) {
        final isPlaying = stateSnapshot.data?.playing ?? false;
        final isLoading =
            stateSnapshot.data?.processingState == ProcessingState.loading;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 关闭
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Get.back(),
                tooltip: '关闭',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),

            const SizedBox(width: 16),

            // 播放/暂停
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filled(
                icon: Icon(
                  isLoading
                      ? Icons.hourglass_top
                      : isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                  size: 28,
                ),
                onPressed: isLoading ? null : () => _togglePlay(),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ),

            const SizedBox(width: 16),

            // 完成裁剪（退出裁剪模式）
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.check, size: 22),
                onPressed: _exitTrimMode,
                tooltip: '完成裁剪',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        );
      },
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
