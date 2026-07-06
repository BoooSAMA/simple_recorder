import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/services/recording_service.dart';

class RecordingManager extends GetxService {
  static RecordingManager get instance => Get.find<RecordingManager>();

  final RxList<RecordingSession> activeSessions = RxList<RecordingSession>();
  final RxInt activeCount = 0.obs;

  /// session 自然结束时广播事件，供续录等外部逻辑监听
  final onSessionEnded = StreamController<RecordingSession>.broadcast();

  int get maxConcurrent => 20;

  bool canStartNew() {
    return activeSessions.length < maxConcurrent;
  }

  RecordingSession? getSession(String taskId) {
    try {
      return activeSessions.firstWhere((s) => s.taskId == taskId);
    } catch (_) {
      return null;
    }
  }

  Future<void> startRecording(RecordingSession session) async {
    // 检查该 taskId 是否已有活跃的录制 session
    var existing = getSession(session.taskId);
    if (existing != null) {
      if (existing.isRecording.value) {
        Log.logPrint("该任务已在录制中: ${session.taskId}");
        return;
      }
      // 旧 session 已自动停止（如网络中断），清理它
      Log.logPrint("清理已停止的旧 session: ${session.taskId}");
      activeSessions.remove(existing);
    }

    if (!canStartNew()) {
      Log.logPrint("已达到最大并行录制数");
      return;
    }

    activeSessions.add(session);
    activeCount.value = activeSessions.length;
    // session 自然结束时（断流/重试耗尽/用户主动停止）自动从列表移除
    session.onFinished = () {
      activeSessions.remove(session);
      activeCount.value = activeSessions.length;
      onSessionEnded.add(session);
    };

    try {
      await session.start();
    } catch (e) {
      // start() 抛异常 → 清理 session，让异常继续传播
      Log.logPrint("session 启动异常: ${session.taskId}, $e");
      activeSessions.remove(session);
      activeCount.value = activeSessions.length;
      rethrow;
    }

    // 如果 start() 未抛异常但 session 实际未启动（如无播放地址），清理它
    if (!session.isRecording.value && activeSessions.contains(session)) {
      Log.logPrint("session 未实际启动，清理: ${session.taskId}");
      activeSessions.remove(session);
      activeCount.value = activeSessions.length;
    }
  }

  /// Returns a map with 'path', 'fileName', 'fileSize' if file was saved.
  Future<Map<String, String>?> stopRecording(String taskId) async {
    var session = getSession(taskId);
    if (session == null) return null;

    await session.stop();
    var path = session.outputPath;
    var fileInfo = <String, String>{};
    if (path.isNotEmpty) {
      var file = File(path);
      if (await file.exists()) {
        fileInfo['path'] = path;
        fileInfo['fileName'] = path.split('/').last;
        var bytes = file.lengthSync();
        fileInfo['fileSize'] = _formatSize(bytes);
      }
    }
    activeSessions.remove(session);
    activeCount.value = activeSessions.length;
    return fileInfo.isNotEmpty ? fileInfo : null;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> cancelRecording(String taskId) async {
    var session = getSession(taskId);
    if (session == null) return;

    await session.cancel();
    activeSessions.remove(session);
    activeCount.value = activeSessions.length;
  }

  /// 清理所有 isRecording=false 的残留 session（刷新/启动时调用）
  void cleanupStaleSessions() {
    var removed = 0;
    for (var session in activeSessions.toList()) {
      if (!session.isRecording.value) {
        activeSessions.remove(session);
        removed++;
      }
    }
    if (removed > 0) {
      activeCount.value = activeSessions.length;
      Log.logPrint("清理了 $removed 个停滞录制会话");
    }
  }

  void stopAll() {
    for (var session in activeSessions.toList()) {
      session.forceStop();
    }
    activeSessions.clear();
    activeCount.value = 0;
  }

  List<RecordingSession> getSessionsByRoom(String roomId) {
    return activeSessions.where((s) => s.roomId == roomId).toList();
  }

  bool isRecording(String taskId) {
    var session = getSession(taskId);
    return session?.isRecording.value ?? false;
  }

  @override
  void onClose() {
    stopAll();
    onSessionEnded.close();
    super.onClose();
  }
}
