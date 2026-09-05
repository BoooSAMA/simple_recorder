import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'package:simple_recorder/modules/recordings/audio_player_sheet.dart';

/// 浮动胶囊式迷你音频播放器
///
/// 占位显示在录音文件列表底部（不遮挡列表交互），
/// 支持播放/暂停、±10s、拖动进度条。
/// 点击展开箭头才打开完整底部面板（含裁剪模式）。
///
/// 注意：父级必须用 [ValueKey]（如 `ValueKey(filePath)`）挂载本组件，
/// 换文件时强制重建 State 以加载新音源；本组件内部不做换源监听。
class FloatingAudioPlayer extends StatefulWidget {
  final String filePath;
  final String fileName;
  final VoidCallback onClose;

  const FloatingAudioPlayer({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.onClose,
  });

  @override
  State<FloatingAudioPlayer> createState() => _FloatingAudioPlayerState();
}

class _FloatingAudioPlayerState extends State<FloatingAudioPlayer> {
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
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _seekBackward() {
    var pos = _player.position;
    var newPos = pos - const Duration(seconds: 10);
    if (newPos < Duration.zero) newPos = Duration.zero;
    _player.seek(newPos);
  }

  void _seekForward() {
    var pos = _player.position;
    var dur = _player.duration;
    var newPos = pos + const Duration(seconds: 10);
    if (dur != null && newPos > dur) newPos = dur;
    _player.seek(newPos);
  }

  /// 打开完整底部面板（含裁剪）。先暂停本播放器，避免双播放器叠声。
  void _openFullPlayer() {
    _player.pause();
    ShowAudioPlayerSheet.show(
      context,
      filePath: widget.filePath,
      fileName: widget.fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_hasError) {
      // 加载失败：不展示播放器，由父级 onClose 语义处理（页面可据此隐藏）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose();
      });
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 第一行：控制按钮 + 文件名 ──
          Row(
            children: [
              // 关闭
              GestureDetector(
                onTap: widget.onClose,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    Icons.close,
                    size: 17,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // 后退 10s
              GestureDetector(
                onTap: _seekBackward,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.replay_10, size: 19),
                ),
              ),
              // 播放/暂停
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, stateSnapshot) {
                  final isPlaying = stateSnapshot.data?.playing ?? false;
                  final isLoading = stateSnapshot.data?.processingState ==
                      ProcessingState.loading;
                  return GestureDetector(
                    onTap: isLoading ? null : _togglePlay,
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
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
                        size: 20,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  );
                },
              ),
              // 前进 10s
              GestureDetector(
                onTap: _seekForward,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.forward_10, size: 19),
                ),
              ),
              const SizedBox(width: 6),
              // 文件名（可变长度）
              Expanded(
                child: Text(
                  widget.fileName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // 展开完整播放器
              GestureDetector(
                onTap: _openFullPlayer,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: 19,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          // ── 第二行：可拖进度条 ──
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
                  return SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              trackHeight: 3,
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12),
                              activeTrackColor: theme.colorScheme.primary,
                              inactiveTrackColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              thumbColor: theme.colorScheme.primary,
                            ),
                            child: Slider(
                              value: progress,
                              onChanged: (v) {
                                final seekPos = Duration(
                                  milliseconds:
                                      (total.inMilliseconds * v).round(),
                                );
                                _player.seek(seekPos);
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(total),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurface.withAlpha(120),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
