import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

/// 底部弹出音频播放器
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

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
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
    _player.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var bottomInset = MediaQuery.of(context).padding.bottom;

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
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          if (_hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.error_outline,
                      size: 40, color: theme.colorScheme.error),
                  const SizedBox(height: 8),
                  Text("无法播放此文件",
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Get.back(),
                    child: const Text("关闭"),
                  ),
                ],
              ),
            )
          else ...[
            // ── 文件名 ──
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                widget.fileName,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

            // ── 进度条 ──
            StreamBuilder<Duration?>(
              stream: _player.durationStream,
              builder: (context, durSnapshot) {
                var duration = durSnapshot.data ?? Duration.zero;

                return StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, posSnapshot) {
                    var position = posSnapshot.data ?? Duration.zero;
                    var progress = duration.inMilliseconds > 0
                        ? (position.inMilliseconds /
                                duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Slider
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            trackHeight: 4,
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (v) {
                              var seekPos = Duration(
                                milliseconds:
                                    (duration.inMilliseconds * v).round(),
                              );
                              _player.seek(seekPos);
                            },
                          ),
                        ),

                        // 时间标签
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(150),
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(150),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 8),

            // ── 播放控制按钮 ──
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, stateSnapshot) {
                var isPlaying = stateSnapshot.data?.playing ?? false;
                var isLoading = stateSnapshot.data?.processingState ==
                    ProcessingState.loading;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 关闭
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                      tooltip: "关闭",
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
                        onPressed:
                            isLoading ? null : () => _togglePlay(),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // 占位（保持对称）
                    const SizedBox(width: 40, height: 40),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }
}
