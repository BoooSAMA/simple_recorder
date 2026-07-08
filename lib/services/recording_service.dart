import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class RecordingSession {
  final String taskId;
  final String roomId;
  final String siteId;
  final String userName;

  final RxBool isRecording = false.obs;
  final RxString duration = "00:00".obs;
  final RxString fileSize = "".obs;
  final RxInt retryCount = 0.obs;
  final RxString lastError = "".obs;

  /// RecordingManager 设置的清理回调，session 自然结束时自动通知
  void Function()? onFinished;

  int? _sessionId;
  Timer? _timer;
  int _seconds = 0;
  int _retries = 0;
  static const int maxRetries = 3;
  String _outputPath = "";
  String get outputPath => _outputPath;
  bool _discardRequested = false;
  DateTime? _startTime;
  Completer<void>? _finishCompleter;

  String Function()? _getPlayUrl;
  Future<void> Function()? _onRefreshPlayUrl;
  Map<String, String>? Function()? _getHeaders;

  RecordingSession({
    required this.taskId,
    required this.roomId,
    required this.siteId,
    required this.userName,
  });

  void configure({
    required String Function() getPlayUrl,
    required Future<void> Function() onRefreshPlayUrl,
    required Map<String, String>? Function() getHeaders,
  }) {
    _getPlayUrl = getPlayUrl;
    _onRefreshPlayUrl = onRefreshPlayUrl;
    _getHeaders = getHeaders;
  }

  Future<String> _getWritableSaveDir() async {
    var preferredDir = AppSettingsController.instance.audioSavePath.value;
    if (preferredDir.isNotEmpty) {
      preferredDir = preferredDir.replaceAll(RegExp(r'/+$'), '');
      var dir = Directory(preferredDir);
      if (await dir.exists()) {
        try {
          var testFile = File(
            '$preferredDir/.write_test_${DateTime.now().millisecondsSinceEpoch}',
          );
          await testFile.writeAsString('test');
          await testFile.delete();
          return preferredDir;
        } catch (e) {
          Log.logPrint("自定义录音路径不可写($preferredDir): $e");
        }
      }
    }
    var dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// 唤醒锁计数，多个录制同时开始时只需获取一次
  static int _wakelockRefCount = 0;

  /// 获取唤醒锁（计数引用，仅在首次真正获取）
  static Future<void> _acquireWakelock() async {
    if (_wakelockRefCount == 0) {
      await WakelockPlus.enable();
      Log.logPrint("唤醒锁已获取（屏幕常亮 + 阻止 CPU 休眠）");
    }
    _wakelockRefCount++;
  }

  /// 释放唤醒锁（计数引用，仅在最后一个录制结束时真正释放）
  static Future<void> _releaseWakelock() async {
    _wakelockRefCount--;
    if (_wakelockRefCount <= 0) {
      _wakelockRefCount = 0;
      await WakelockPlus.disable();
      Log.logPrint("唤醒锁已释放");
    }
  }

  /// 前台服务计数（与唤醒锁联动，多个录制只启动一个前台服务）
  static int _foregroundServiceRefCount = 0;
  /// 标记前台服务是否实际启动成功（用于权限不足时跳过停止逻辑）
  static bool _foregroundServiceActuallyStarted = false;

  /// 创建前台服务所需的通知渠道（某些 ROM 不会自动创建）
  static Future<void> _ensureForegroundNotificationChannel() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = AndroidNotificationChannel(
        'simple_recorder_channel',
        '录制服务',
        description: 'Simple Recorder 前台录制服务通知',
        importance: Importance.low,
      );
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {
      Log.logPrint("创建前台服务通知渠道失败: $e");
    }
  }

  /// 启动前台服务（首次录制时拉起来）
  static Future<void> _acquireForegroundService() async {
    if (_foregroundServiceRefCount == 0) {
      // Android 13+ (API 33) 需要 POST_NOTIFICATIONS 权限才能 startForeground
      if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (!status.isGranted) {
          Log.logPrint("通知权限未授予，跳过前台服务启动（后台录制可能被系统杀死）");
          _foregroundServiceRefCount++;
          return;
        }
      }

      // 显式创建通知渠道，避免某些 ROM 上 flutter_background_service 内部创建失败
      await _ensureForegroundNotificationChannel();

      final service = FlutterBackgroundService();
      await service.startService();
      _foregroundServiceActuallyStarted = true;
      Log.logPrint("前台服务已启动");
    }
    _foregroundServiceRefCount++;
  }

  /// 为外部模块（如开播通知）获取前台服务保活
  static Future<void> acquireForegroundService() {
    return _acquireForegroundService();
  }

  /// 外部模块释放前台服务保活
  static Future<void> releaseForegroundService() {
    return _releaseForegroundService();
  }

  /// 停止前台服务（最后一次录制结束时停掉）
  static Future<void> _releaseForegroundService() async {
    _foregroundServiceRefCount--;
    if (_foregroundServiceRefCount <= 0) {
      _foregroundServiceRefCount = 0;
      if (_foregroundServiceActuallyStarted) {
        final service = FlutterBackgroundService();
        service.invoke('stopService');
        _foregroundServiceActuallyStarted = false;
        Log.logPrint("前台服务已停止");
      }
    }
  }

  Future<void> start() async {
    if (isRecording.value) return;
    _finished = false;
    _sessionGeneration++; // 标记旧 FFmpeg 回调为过期

    // 获取唤醒锁和前台服务
    await _acquireWakelock();
    await _acquireForegroundService();

    var playUrl = _getPlayUrl?.call() ?? "";
    if (playUrl.isEmpty) {
      lastError.value = "没有可用的播放地址";
      _releaseWakelock();
      _releaseForegroundService();
      return;
    }

    var now = DateTime.now();
    var timestamp =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}"
        "_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}";

    var saveDir = await _getWritableSaveDir();

    if (AppSettingsController.instance.autoSaveToFolder.value) {
      saveDir = "$saveDir/$userName";
      var dir = Directory(saveDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    _outputPath = "$saveDir/${userName}_$timestamp.ts";
    _startTime = DateTime.now();
    _discardRequested = false;
    _retries = 0;
    _stopRequested = false;

    // 读取切片设置
    var sliceEnabled = AppSettingsController.instance.autoSliceEnabled.value;
    var sliceMinutes = AppSettingsController.instance.autoSliceIntervalMinutes.value;
    _sliceIntervalSeconds = (sliceEnabled && sliceMinutes > 0) ? sliceMinutes * 60 : 0;

    // 优化：文件大小每 5 秒轮询一次，时长每秒更新
    var sizeTickCounter = 0;
    await _startFFmpegSession(playUrl);

    isRecording.value = true;
    _seconds = 0;
    duration.value = "00:00";
    fileSize.value = "";
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      var m = (_seconds ~/ 60).toString().padLeft(2, '0');
      var s = (_seconds % 60).toString().padLeft(2, '0');
      duration.value = "$m:$s";
      // 文件大小每 5 秒轮询一次，减少系统调用
      if (sizeTickCounter % 5 == 0) {
        fileSize.value = _formatFileSize(_outputPath);
        // 停滞检测：服务器限流导致 FFmpeg 无限重连，文件始终 0B
        if (_seconds > 90 && fileSize.value == "0 B") {
          lastError.value = "录制停滞，可能服务器限流，已自动结束";
          Log.logPrint("检测到录制停滞，自动结束: $_outputPath, ${_seconds}s");
          _onFinished();
          return;
        }
        if (_seconds > 60 && fileSize.value == "0 B") {
          lastError.value = "录制异常：长时间无数据写入（可能服务器限流）";
          Log.logPrint("录制停滞预警: $_outputPath, ${_seconds}s");
        }
      }
      // 切片检测：达到设定秒数时自动切分
      if (!_isSlicing && _sliceIntervalSeconds > 0 && _seconds > 0 &&
          _seconds % _sliceIntervalSeconds == 0) {
        _isSlicing = true;
        var slicePath = _outputPath;
        Log.logPrint("自动切片触发: $slicePath, 已录制 ${_seconds}s");
        // 1. 取消当前定时器，防止切片进行中再次触发
        _timer?.cancel();
        _timer = null;
        // 2. 取消 FFmpeg 进程（发送信号让它正常退出、写入文件尾）
        if (_sessionId != null) {
          FFmpegKit.cancel(_sessionId);
          _sessionId = null;
        }
        isRecording.value = false;
        // 3. 给 FFmpeg 一点时间完成退出清理，然后直接走切片完成流程
        //    不依赖 FFmpegKit 的异步回调（某些情况下回调可能丢失）
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_isSlicing) {
            Log.logPrint("切片: FFmpeg 已停止，调用 _onFinished");
            _onFinished();
          }
        });
        return;
      }
      sizeTickCounter++;
    });
  }

  Future<void> _startFFmpegSession(String playUrl) async {
    var args = <String>['-y'];

    var headers = _getHeaders?.call();
    if (headers != null && headers.containsKey('user-agent')) {
      args.addAll(['-user_agent', headers['user-agent']!]);
    }
    if (headers != null && headers.isNotEmpty) {
      var filtered = Map<String, String>.from(headers);
      filtered.remove('user-agent');
      if (filtered.isNotEmpty) {
        var headerStr =
            filtered.entries.map((e) => '${e.key}: ${e.value}').join('\r\n');
        args.addAll(['-headers', '$headerStr\r\n']);
      }
    }

    args.addAll([
      '-reconnect', '1',
      '-reconnect_streamed', '1',
      '-reconnect_delay_max', '5',
      '-timeout', '10000000',
    ]);

    args.addAll(['-i', playUrl]);
    args.addAll(['-c:a', 'copy', '-vn']);
    args.addAll(['-f', 'mpegts', _outputPath]);

    if (_retries == 0) {
      Log.logPrint("开始录音: ${args.join(' ')}");
    }

    // 记录当前代际编号，回调中检查是否已过期
    // 防止切片重启后旧回调误操作新 session 的文件/状态
    var capturedGen = _sessionGeneration;

    var session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        // 如果代际编号已过期，说明这个回调属于旧 session，忽略
        if (capturedGen != _sessionGeneration) return;

        var returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          Log.logPrint("录音成功完成: $_outputPath");
          await _onFinished();
        } else if (ReturnCode.isCancel(returnCode)) {
          if (_discardRequested) {
            _discardRequested = false;
            try {
              var file = File(_outputPath);
              if (file.existsSync()) file.deleteSync();
            } catch (_) {}
          }
          await _onFinished();
        } else {
          // 获取失败日志（仅在出错时读取）
          var output = await session.getOutput();
          // 只记录输出中的错误行（error/warning），避免保存重复的长日志
          if (output != null && output.length < 2000) {
            lastError.value = output;
          } else if (output != null) {
            var errorLines = output.split('\n').where((l) => l.contains('Error') || l.contains('error')).join('\n');
            lastError.value = errorLines.isNotEmpty ? errorLines : output.substring(0, 1500);
          } else {
            lastError.value = "未知错误";
          }
          Log.logPrint("录音失败: ${lastError.value}");
          _scheduleRetry(playUrl);
        }
      },
      // 不传 logCallback，避免每条 FFmpeg 信息都回调到 Dart 层
    );
    _sessionId = session.getSessionId();
  }

  void _scheduleRetry(String playUrl) {
    if (_retries >= maxRetries) {
      Log.logPrint("录音重连失败，已达最大重试次数");
      lastError.value = "重连失败，已达最大重试次数";
      _isInterrupted = true;
      _onFinished();
      return;
    }
    _retries++;
    retryCount.value = _retries;
    // 乘性退避：第1次2秒，第2次4秒，第3次6秒（上限）
    var delay = Duration(seconds: 2 * _retries);
    Log.logPrint("录音重连: 第$_retries/$maxRetries 次，${delay.inSeconds}秒后重试");

    Future.delayed(delay, () async {
      if (!isRecording.value) {
        // 用户已在重试窗口内取消了录制，完整清理
        _onFinished();
        return;
      }
      await _onRefreshPlayUrl?.call();
      // 使用刷新后的 URL 重试，而非旧的 playUrl 参数
      var freshUrl = _getPlayUrl?.call() ?? playUrl;
      await _startFFmpegSession(freshUrl);
    });
  }

  Future<void> stop() async {
    _stopRequested = true;
    _discardRequested = false;
    _finishCompleter = Completer<void>();
    _doCancelFFmpeg();
    await _finishCompleter!.future;
  }

  Future<void> cancel() async {
    _stopRequested = true;
    _discardRequested = true;
    _finishCompleter = Completer<void>();
    _doCancelFFmpeg();
    await _finishCompleter!.future;
  }

  void forceStop() {
    _timer?.cancel();
    _timer = null;
    if (_sessionId != null) {
      FFmpegKit.cancel(_sessionId);
      _sessionId = null;
    }
    isRecording.value = false;
    _releaseWakelock();
    _releaseForegroundService();
    _finishCompleter?.complete();
  }

  void _doCancelFFmpeg() {
    bool hadActiveSession = _sessionId != null;
    if (_sessionId != null) {
      FFmpegKit.cancel(_sessionId);
      _sessionId = null;
    }
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
    // 无活跃 FFmpeg 会话（如重试延迟窗口中），
    // 回调不会触发，需手动完成清理
    if (!hadActiveSession) {
      _onFinished();
    }
  }

  bool _finished = false;
  bool _isInterrupted = false;
  bool _isSlicing = false;
  int _sliceIntervalSeconds = 0;
  bool _stopRequested = false;

  /// FFmpeg session 代际编号，每次 start() 递增。
  /// 旧 FFmpeg 回调检查此值，如果不再匹配则静默放弃处理，
  /// 防止切片重启后旧回调误操作新 session 的文件/状态。
  int _sessionGeneration = 0;

  /// 是否为用户主动停止（而非直播结束/重试耗尽导致的自然结束）
  bool get isUserStopped => _stopRequested;

  Future<void> _onFinished() async {
    if (_finished) return; // 防止重入（retry + cancel 双路径可能同时触发）
    _finished = true;
    if (_startTime != null && _outputPath.isNotEmpty && !_discardRequested) {
      await _renameFileWithEndTime();
      // 成功完成录音后，自动解包 TS → 目标格式
      if (_outputPath.endsWith('.ts')) {
        await _autoUnpackToTargetFormat();
      }
    }

    // === 切片分支：切片时重置状态并重新开始，不通知 manager ===
    if (_isSlicing && !_stopRequested) {
      _sessionGeneration++; // 优先递增代际，阻止旧 FFmpeg 回调进入
      _isSlicing = false;
      _finished = false; // 允许下次切片或完成（旧回调已被代际检查拦截）
      _startTime = null;
      _sessionId = null;
      _timer?.cancel();
      _timer = null;
      isRecording.value = false;
      // 释放引用计数（让 start() 重新获取，保持平衡）
      _releaseWakelock();
      _releaseForegroundService();
      // 刷新播放地址（即使刷新失败也继续尝试重启，旧 URL 可能仍有效）
      try {
        await _onRefreshPlayUrl?.call();
      } catch (e) {
        Log.logPrint("切片刷新播放地址失败(继续尝试): $e");
      }
      Log.logPrint("切片完成，开始下一段录制");
      try {
        start();
      } catch (e) {
        Log.logPrint("切片重启录制失败，清理会话: $e");
        // 重启失败时完整清理，防止 session 挂起
        _releaseWakelock();
        _releaseForegroundService();
        _finishCompleter?.complete();
        onFinished?.call();
      }
      return;
    }

    // === 正常结束流程 ===
    _startTime = null;
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
    _sessionId = null;
    // 录制结束时释放唤醒锁和前台服务
    _releaseWakelock();
    _releaseForegroundService();
    _finishCompleter?.complete();
    // 通知 RecordingManager 从 activeSessions 中移除
    onFinished?.call();
  }

  /// 将完成录制的 TS 文件自动解包为目标格式（根据设置）
  Future<void> _autoUnpackToTargetFormat() async {
    var tsPath = _outputPath;
    if (tsPath.isEmpty || !tsPath.endsWith('.ts')) return;

    var format = AppSettingsController.instance.audioFormat.value;
    var ext = Constant.audioFormatExtension(format);
    var outputPath = tsPath.replaceAll('.ts', ext);

    // 避免重复解包（目标文件已存在）
    if (File(outputPath).existsSync()) return;

    var codecArgs = Constant.audioFormatFfmpegArgs(format);
    var args = ['-y', '-i', tsPath, ...codecArgs, outputPath];
    Log.logPrint("自动解包 TS → ${Constant.audioFormatDisplayName(format)}: ${args.join(' ')}");

    var completer = Completer<void>();
    await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
      var returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        Log.logPrint("自动解包成功: $outputPath");
        _outputPath = outputPath;

        // 解包成功后，按设置决定是否删除 TS 文件
        if (AppSettingsController.instance.deleteTsAfterUnpack.value) {
          try {
            var tsFile = File(tsPath);
            if (await tsFile.exists()) {
              await tsFile.delete();
              Log.logPrint("已删除源 TS 文件: $tsPath");
            }
          } catch (e) {
            Log.logPrint("删除源 TS 文件失败: $e");
          }
        }
      } else {
        Log.logPrint("自动解包失败: $tsPath");
      }
      completer.complete();
    });
    await completer.future;
  }

  Future<void> _renameFileWithEndTime() async {
    var file = File(_outputPath);
    if (!await file.exists()) return;

    var dir = file.parent.path;
    var endTime = DateTime.now();
    var start = _startTime!;
    var datePart =
        "${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}";
    var startPart =
        "${start.hour.toString().padLeft(2, '0')}-${start.minute.toString().padLeft(2, '0')}";
    var endPart =
        "${endTime.hour.toString().padLeft(2, '0')}-${endTime.minute.toString().padLeft(2, '0')}";
    var suffix = _isInterrupted ? '_interrupted' : '';
    var newName = "${userName}_${datePart}_${startPart}_$endPart$suffix.ts";
    var newPath = "$dir/$newName";
    try {
      await file.rename(newPath);
      _outputPath = newPath;
    } catch (e) {
      Log.d("录音文件重命名失败: $e");
    }
  }

  String _formatFileSize(String path) {
    try {
      var file = File(path);
      if (file.existsSync()) {
        var bytes = file.lengthSync();
        if (bytes < 1024) return "${bytes}B";
        if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)}k";
        if (bytes < 1024 * 1024 * 1024) {
          return "${(bytes / (1024 * 1024)).toStringAsFixed(1)}m";
        }
        return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}g";
      }
    } catch (_) {}
    return "0B";
  }
}
