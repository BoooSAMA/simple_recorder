import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';

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

  /// 启动前台服务（首次录制时拉起来）
  static Future<void> _acquireForegroundService() async {
    if (_foregroundServiceRefCount == 0) {
      final service = FlutterBackgroundService();
      await service.startService();
      Log.logPrint("前台服务已启动");
    }
    _foregroundServiceRefCount++;
  }

  /// 停止前台服务（最后一次录制结束时停掉）
  static Future<void> _releaseForegroundService() async {
    _foregroundServiceRefCount--;
    if (_foregroundServiceRefCount <= 0) {
      _foregroundServiceRefCount = 0;
      final service = FlutterBackgroundService();
      service.invoke('stopService');
      Log.logPrint("前台服务已停止");
    }
  }

  Future<void> start() async {
    if (isRecording.value) return;

    // 录制开始时获取唤醒锁，保持屏幕常亮 + 阻止 CPU 休眠
    await _acquireWakelock();
    // 启动前台服务，防止系统杀死后台录制进程
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
      '-reconnect_at_eof', '1',
      '-reconnect_delay_max', '5',
      '-timeout', '10000000',
    ]);

    args.addAll(['-i', playUrl]);
    args.addAll(['-c:a', 'copy', '-vn']);
    args.addAll(['-f', 'mpegts', _outputPath]);

    if (_retries == 0) {
      Log.logPrint("开始录音: ${args.join(' ')}");
    }

    var session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
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
      _onFinished();
      return;
    }
    _retries++;
    retryCount.value = _retries;
    // 乘性退避：第1次2秒，第2次4秒，第3次6秒（上限）
    var delay = Duration(seconds: 2 * _retries);
    Log.logPrint("录音重连: 第$_retries/$maxRetries 次，${delay.inSeconds}秒后重试");

    Future.delayed(delay, () async {
      if (!isRecording.value) return;
      await _onRefreshPlayUrl?.call();
      await _startFFmpegSession(playUrl);
    });
  }

  Future<void> stop() async {
    _discardRequested = false;
    _finishCompleter = Completer<void>();
    _doCancelFFmpeg();
    await _finishCompleter!.future;
  }

  Future<void> cancel() async {
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
    if (_sessionId != null) {
      FFmpegKit.cancel(_sessionId);
      _sessionId = null;
    }
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
  }

  Future<void> _onFinished() async {
    if (_startTime != null && _outputPath.isNotEmpty && !_discardRequested) {
      await _renameFileWithEndTime();
      // 成功完成录音后，自动解包 TS → M4A
      if (_outputPath.endsWith('.ts')) {
        await _autoUnpackToM4A();
      }
    }
    _startTime = null;
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
    _sessionId = null;
    // 录制结束时释放唤醒锁和前台服务
    _releaseWakelock();
    _releaseForegroundService();
    _finishCompleter?.complete();
  }

  /// 将完成录制的 TS 文件自动解包为 M4A（纯 remux，`-c:a copy`，不重编码）
  Future<void> _autoUnpackToM4A() async {
    var tsPath = _outputPath;
    if (tsPath.isEmpty || !tsPath.endsWith('.ts')) return;

    var m4aPath = tsPath.replaceAll('.ts', '.m4a');
    // 避免重复解包（如手动解包工具已处理过）
    if (File(m4aPath).existsSync()) return;

    var args = ['-y', '-i', tsPath, '-c:a', 'copy', '-vn', m4aPath];
    Log.logPrint("自动解包 TS → M4A: ${args.join(' ')}");

    var completer = Completer<void>();
    FFmpegKit.executeWithArgumentsAsync(args, (session) async {
      var returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        Log.logPrint("自动解包成功: $m4aPath");
        _outputPath = m4aPath; // 更新路径指向 M4A
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
    var newName = "${userName}_${datePart}_${startPart}_$endPart.ts";
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
