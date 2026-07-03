import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/log.dart';

class UnpackResult {
  final bool success;
  final String path;
  final String? error;

  UnpackResult({
    required this.success,
    required this.path,
    this.error,
  });
}

class TsUnpackService {
  /// 解包 TS 文件为目标音频格式
  ///
  /// [tsPath] TS 文件路径
  /// [targetFormat] 目标格式 (m4a, mp3, flac, wav, ogg)，默认 m4a
  /// [onProgress] 进度回调 (0.0 ~ 1.0)
  static Future<UnpackResult> unpack(
    String tsPath, {
    String targetFormat = 'm4a',
    void Function(double)? onProgress,
  }) async {
    var ext = Constant.audioFormatExtension(targetFormat);
    var outputPath = tsPath.replaceAll('.ts', ext);

    // 检查同名文件是否已存在
    if (File(outputPath).existsSync()) {
      return UnpackResult(
        success: false,
        path: tsPath,
        error: "同名 ${ext.toUpperCase()} 文件已存在",
      );
    }

    // ── 先通过 FFprobe 获取文件总时长 ──
    var totalDuration = await _probeDuration(tsPath);
    if (totalDuration == 0) {
      Log.logPrint("FFprobe 未能获取时长，将仅使用文件尺寸估算进度");
    } else {
      Log.logPrint("FFprobe 获取总时长: ${totalDuration}s");
    }

    var codecArgs = Constant.audioFormatFfmpegArgs(targetFormat);
    var args = ['-y', '-i', tsPath, ...codecArgs, outputPath];
    Log.logPrint("开始解包: ffmpeg ${args.join(' ')}");

    var completer = Completer<UnpackResult>();
    var inputFile = File(tsPath);
    var inputSize = inputFile.lengthSync();

    // 文件尺寸进度监测（作为后备）
    Timer? progressTimer;
    if (onProgress != null) {
      progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!completer.isCompleted) {
          var outputFile = File(outputPath);
          if (outputFile.existsSync()) {
            var written = outputFile.lengthSync();
            // 写入比例：纯音频输出约占总 TS 大小的 5~20%
            // 用 0.15 作为中间估计值
            var ratio = inputSize > 0
                ? (written / (inputSize * 0.15)).clamp(0.0, 0.95)
                : 0.0;
            onProgress(ratio);
          }
        }
      });
    }

    await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        progressTimer?.cancel();
        var returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          Log.logPrint("解包成功: $outputPath");
          onProgress?.call(1.0);
          completer.complete(UnpackResult(success: true, path: tsPath));
        } else if (ReturnCode.isCancel(returnCode)) {
          completer.complete(UnpackResult(
            success: false,
            path: tsPath,
            error: "已取消",
          ));
        } else {
          var output = await session.getOutput();
          var errMsg = output ?? "解包失败";
          Log.logPrint("解包失败: $errMsg");
          completer.complete(UnpackResult(
            success: false,
            path: tsPath,
            error: errMsg,
          ));
        }
      },
      (log) {
        var msg = log.getMessage();
        if (onProgress == null) return;

        // 尝试从 FFmpeg 日志解析总时长（兜底）
        if (totalDuration == 0) {
          var durMatch = RegExp(
            r'Duration:\s*(\d{2}):(\d{2}):(\d{2})\.\d{2}',
          ).firstMatch(msg);
          if (durMatch != null) {
            totalDuration = _parseTimeToSeconds(
              durMatch.group(1)!,
              durMatch.group(2)!,
              durMatch.group(3)!,
            );
            Log.logPrint("日志解析总时长: ${totalDuration}s");
          }
        }

        // 解析当前位置: "time=01:23:45.67"
        if (totalDuration > 0) {
          var timeMatch = RegExp(
            r'time=(\d{2}):(\d{2}):(\d{2})\.\d{2}',
          ).firstMatch(msg);
          if (timeMatch != null) {
            var current = _parseTimeToSeconds(
              timeMatch.group(1)!,
              timeMatch.group(2)!,
              timeMatch.group(3)!,
            );
            onProgress((current / totalDuration).clamp(0.0, 1.0));
          }
        }
      },
    );

    return completer.future;
  }

  /// 使用 FFprobe 获取媒体文件时长（秒）
  static Future<double> _probeDuration(String path) async {
    try {
      var session = await FFprobeKit.getMediaInformation(path);
      var info = session.getMediaInformation();
      var durationStr = info?.getDuration();
      if (durationStr != null && durationStr.isNotEmpty) {
        var d = double.tryParse(durationStr);
        if (d != null && d > 0) return d;
      }
    } catch (e) {
      Log.logPrint("FFprobe 获取时长失败: $e");
    }
    return 0;
  }

  static double _parseTimeToSeconds(String h, String m, String s) {
    return int.parse(h) * 3600.0 +
        int.parse(m) * 60.0 +
        int.parse(s);
  }
}
