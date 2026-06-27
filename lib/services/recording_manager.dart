import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/services/recording_service.dart';

class RecordingManager extends GetxService {
  static RecordingManager get instance => Get.find<RecordingManager>();

  final RxList<RecordingSession> activeSessions = RxList<RecordingSession>();
  final RxInt activeCount = 0.obs;

  int get maxConcurrent => 10;

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
    if (!canStartNew()) {
      Log.logPrint("已达到最大并行录制数");
      return;
    }

    if (getSession(session.taskId) != null) {
      Log.logPrint("该任务已在录制中: ${session.taskId}");
      return;
    }

    activeSessions.add(session);
    activeCount.value = activeSessions.length;
    await session.start();
  }

  Future<void> stopRecording(String taskId) async {
    var session = getSession(taskId);
    if (session == null) return;

    await session.stop();
    activeSessions.remove(session);
    activeCount.value = activeSessions.length;
  }

  Future<void> cancelRecording(String taskId) async {
    var session = getSession(taskId);
    if (session == null) return;

    await session.cancel();
    activeSessions.remove(session);
    activeCount.value = activeSessions.length;
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
    super.onClose();
  }
}
