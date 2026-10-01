import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';

class UnpackResult {
  final bool success;
  final String path;
  final String? error;
  /// 源 TS 是否已删除（开关关闭视为主动保留，不算失败）
  final bool tsDeleted;

  UnpackResult({
    required this.success,
    required this.path,
    this.error,
    this.tsDeleted = true,
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
    void Function(String)? onLog,
    void Function(int writtenBytes, int inputBytes)? onSize,
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

    // 进度统一出口：只允许前进，忽略回退值，避免进度条反复跳动
    var lastProgress = 0.0;
    void emitProgress(double p) {
      if (p < lastProgress || p > 1.0) return;
      lastProgress = p;
      onProgress?.call(p);
    }

    // 文件尺寸进度监测：仅当无法从 FFmpeg 日志获取精确时长时作为后备
    Timer? progressTimer;
    if (onProgress != null || onSize != null) {
      progressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        // totalDuration > 0 说明已有精确进度源（FFprobe 或日志 Duration 行），
        // 此时文件尺寸估算不再推值，避免与日志 time= 解析冲突导致进度跳动
        if (!completer.isCompleted && totalDuration == 0) {
          var outputFile = File(outputPath);
          if (outputFile.existsSync()) {
            var written = outputFile.lengthSync();
            // 写入量展示（悬浮窗内部工作行用）
            onSize?.call(written, inputSize);
            // 写入比例：纯音频输出约占总 TS 大小的 5~20%
            // 用 0.15 作为中间估计值
            var ratio = inputSize > 0
                ? (written / (inputSize * 0.15)).clamp(0.0, 0.95)
                : 0.0;
            emitProgress(ratio);
          }
        } else if (!completer.isCompleted && onSize != null) {
          // 有精确进度源时仍上报写入量（仅展示，不推进度）
          try {
            var outputFile = File(outputPath);
            if (outputFile.existsSync()) {
              onSize(outputFile.lengthSync(), inputSize);
            }
          } catch (_) {}
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
          emitProgress(1.0);

          // 按设置决定是否删除源 TS 文件（带重试：FFmpeg 刚结束时
          // 文件句柄可能未释放，一次失败就放弃会导致 TS 残留）
          var tsDeleted = true;
          if (AppSettingsController.instance.deleteTsAfterUnpack.value) {
            tsDeleted = await _deleteTsWithRetry(tsPath);
          }

          completer.complete(UnpackResult(
              success: true, path: tsPath, tsDeleted: tsDeleted));
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
        // 原始日志行透传（调用方提取内部状态展示）
        onLog?.call(msg);
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
            emitProgress(current / totalDuration);
          }
        }
      },
    );

    return completer.future;
  }

  /// 删除源 TS（最多 3 次，间隔 500ms），返回是否已删除
  static Future<bool> _deleteTsWithRetry(String tsPath) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        var tsFile = File(tsPath);
        if (!await tsFile.exists()) return true; // 已不在，视为成功
        await tsFile.delete();
        Log.logPrint("已删除源 TS 文件: $tsPath");
        return true;
      } catch (e) {
        Log.logPrint("删除源 TS 文件失败(第${attempt + 1}次): $e");
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return false;
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
