import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<void> start() async {
    if (isRecording.value) return;

    var playUrl = _getPlayUrl?.call() ?? "";
    if (playUrl.isEmpty) {
      lastError.value = "没有可用的播放地址";
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
      fileSize.value = _formatFileSize(_outputPath);
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
          var output = await session.getOutput();
          lastError.value = output ?? "未知错误";
          Log.logPrint("录音失败: ${lastError.value}");
          _scheduleRetry(playUrl);
        }
      },
      (log) {
        Log.logPrint("FFmpeg: ${log.getMessage()}");
      },
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
    Log.logPrint("录音重连: 第$_retries/$maxRetries 次，2秒后重试");

    Future.delayed(const Duration(seconds: 2), () async {
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
    }
    _startTime = null;
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
    _sessionId = null;
    _finishCompleter?.complete();
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
