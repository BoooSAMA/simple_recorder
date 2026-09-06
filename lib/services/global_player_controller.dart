import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

/// 播放队列中的一首（路径 + 文件名）
class QueueTrack {
  final String path;
  final String name;

  const QueueTrack(this.path, this.name);
}

/// 全局音频播放器（常驻单例，跨页面保持播放）
///
/// - [AudioPlayer] 实例全局唯一，随 App 生命周期存在，跳转页面不中断播放。
/// - 播放控制（播放/暂停/±10s/拖进度）与裁剪（针筒选段/试听/FFmpeg 执行）
///   都收敛在这里，UI 层（[FloatingAudioPlayer]）只做纯展示。
/// - FFmpeg 裁剪为异步后台执行，不阻塞 UI。
class GlobalPlayerController extends GetxController {
  static GlobalPlayerController get instance =>
      Get.find<GlobalPlayerController>();

  late final AudioPlayer player;

  /// 当前播放文件路径（空 = 播放器隐藏）
  final currentPath = ''.obs;

  /// 当前播放文件名（浮动播放器标题）
  final currentName = ''.obs;

  bool get isVisible => currentPath.value.isNotEmpty;

  // ── 收起态（贴屏幕左侧小条，仅播放键 + 展开键，音乐不停） ──
  final isCollapsed = false.obs;

  void toggleCollapse() {
    if (!isCollapsed.value) {
      // 收起时先退出裁剪模式
      exitTrimMode();
    }
    isCollapsed.value = !isCollapsed.value;
  }

  // ── 播放队列 / 上下首 ──
  List<QueueTrack> _queue = const [];
  final queueIndex = (-1).obs;

  bool get hasPrev => queueIndex.value > 0;
  bool get hasNext =>
      queueIndex.value >= 0 && queueIndex.value < _queue.length - 1;

  // ── 双态功能键 ──
  /// 单曲循环（LoopMode.one）
  final loopOne = false.obs;

  /// 自动连播（播完自动下一首，默认开）
  final autoPlay = true.obs;

  // ── 裁剪模式状态 ──
  final isTrimMode = false.obs;
  final trimStart = 0.0.obs; // 0.0 ~ 1.0
  final trimEnd = 1.0.obs;
  final isTrimming = false.obs;
  final isPreviewingTrim = false.obs;
  final trimSuccess = false.obs;
  final trimmedFileName = ''.obs;
  StreamSubscription<Duration>? _previewSub;

  @override
  void onInit() {
    super.onInit();
    player = AudioPlayer();
    // 播完自动下一首（单曲循环时 LoopMode.one 会自动重播，不会走到 completed）
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && autoPlay.value) {
        playNext();
      }
    });
  }

  @override
  void onClose() {
    _previewSub?.cancel();
    player.dispose();
    super.onClose();
  }

  // ── 播放控制 ──

  /// 播放指定文件（点另一文件即换源重播）
  ///
  /// [queue]/[index] 为该文件所在的播放队列（同组文件列表），
  /// 用于上一首/下一首/自动连播；不传则上下首按钮禁用。
  Future<void> playFile(
    String path,
    String name, {
    List<QueueTrack> queue = const [],
    int index = -1,
  }) async {
    await exitTrimMode();
    _queue = queue;
    queueIndex.value = index;
    currentPath.value = path;
    currentName.value = name;
    try {
      await player.stop();
      await player.setAudioSource(
        AudioSource.file(path),
        preload: true,
      );
      await player.play();
    } catch (_) {
      // 文件损坏/消失 → 自动收起播放器
      close();
    }
  }

  Future<void> togglePlay() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  /// 相对快进/快退（秒）
  void seekBySeconds(int seconds) {
    var pos = player.position + Duration(seconds: seconds);
    final dur = player.duration;
    if (pos < Duration.zero) pos = Duration.zero;
    if (dur != null && pos > dur) pos = dur;
    player.seek(pos);
  }

  /// 按比例跳转（0.0 ~ 1.0）
  void seekRatio(double ratio) {
    final total = player.duration;
    if (total == null || total.inMilliseconds <= 0) return;
    player.seek(
      Duration(milliseconds: (total.inMilliseconds * ratio).round()),
    );
  }

  /// 关闭播放器（停止 + 隐藏）
  void close() {
    exitTrimMode();
    player.stop();
    _queue = const [];
    queueIndex.value = -1;
    isCollapsed.value = false;
    currentPath.value = '';
    currentName.value = '';
  }

  // ── 上一首 / 下一首 / 双态键 ──

  Future<void> playPrev() async {
    if (!hasPrev) return;
    final t = _queue[queueIndex.value - 1];
    await playFile(t.path, t.name,
        queue: _queue, index: queueIndex.value - 1);
  }

  Future<void> playNext() async {
    if (!hasNext) return;
    final t = _queue[queueIndex.value + 1];
    await playFile(t.path, t.name,
        queue: _queue, index: queueIndex.value + 1);
  }

  /// 切换单曲循环
  Future<void> toggleLoopOne() async {
    loopOne.value = !loopOne.value;
    await player.setLoopMode(loopOne.value ? LoopMode.one : LoopMode.off);
  }

  /// 切换自动连播
  void toggleAutoPlay() {
    autoPlay.value = !autoPlay.value;
  }

  // ── 裁剪模式 ──

  void enterTrimMode() {
    trimStart.value = 0.0;
    trimEnd.value = 1.0;
    trimSuccess.value = false;
    trimmedFileName.value = '';
    isPreviewingTrim.value = false;
    isTrimMode.value = true;
    player.pause();
  }

  Future<void> exitTrimMode() async {
    await _previewSub?.cancel();
    _previewSub = null;
    isPreviewingTrim.value = false;
    isTrimMode.value = false;
  }

  /// 试听选中的裁剪段
  Future<void> previewTrimSegment() async {
    final duration = player.duration;
    if (duration == null || duration.inMilliseconds <= 0) return;

    final startMs = (duration.inMilliseconds * trimStart.value).round();
    final endMs = (duration.inMilliseconds * trimEnd.value).round();
    if (endMs - startMs < 500) return;

    isPreviewingTrim.value = true;
    await _previewSub?.cancel();

    await player.seek(Duration(milliseconds: startMs));
    await player.play();

    _previewSub = player.positionStream.listen((pos) {
      if (pos.inMilliseconds >= endMs) {
        player.pause();
        _previewSub?.cancel();
        _previewSub = null;
        isPreviewingTrim.value = false;
      }
    });
  }

  Future<void> stopTrimPreview() async {
    await _previewSub?.cancel();
    _previewSub = null;
    await player.stop();
    isPreviewingTrim.value = false;
  }

  /// 执行裁剪（FFmpeg 音频直拷，不重编码，异步后台执行）
  Future<void> executeTrim() async {
    final total = player.duration;
    if (total == null || total.inMilliseconds <= 0) return;

    final startMs = (total.inMilliseconds * trimStart.value).round();
    final endMs = (total.inMilliseconds * trimEnd.value).round();
    if (endMs - startMs < 1000) {
      Get.snackbar('提示', '选中片段太短（至少 1 秒）');
      return;
    }

    isTrimming.value = true;

    final inputPath = currentPath.value;
    final dotIndex = inputPath.lastIndexOf('.');
    final sourceExt = dotIndex > 0 ? inputPath.substring(dotIndex) : '.m4a';
    final baseName =
        inputPath.substring(0, dotIndex > 0 ? dotIndex : inputPath.length);
    var outputPath = '${baseName}_trimmed$sourceExt';

    // 避免覆盖
    int counter = 1;
    while (File(outputPath).existsSync()) {
      outputPath = '${baseName}_trimmed($counter)$sourceExt';
      counter++;
    }

    final args = [
      '-y',
      '-i',
      inputPath,
      '-ss',
      formatFfmpeg(Duration(milliseconds: startMs)),
      '-to',
      formatFfmpeg(Duration(milliseconds: endMs)),
      '-c:a',
      'copy',
      '-vn',
      outputPath,
    ];

    final completer = Completer<void>();
    await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        trimSuccess.value = true;
        trimmedFileName.value = outputPath.split('/').last;
        Get.snackbar('裁剪成功', trimmedFileName.value);
      } else {
        trimSuccess.value = false;
        trimmedFileName.value = '';
        Get.snackbar('裁剪失败', '请检查文件是否损坏');
      }
      completer.complete();
    });
    await completer.future;

    isTrimming.value = false;
  }

  // ── 时间格式化（UI 共用） ──

  static String formatDuration(Duration d) {
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
  static String formatFfmpeg(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
