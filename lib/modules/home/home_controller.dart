import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/services/recording_service.dart';
import 'package:simple_recorder/app/sites.dart';

class HomeController extends GetxController {
  final followList = <FollowUser>[].obs;
  final isLoading = false.obs;

  final Map<String, Rx<int>> liveStatusMap = {};
  final Map<String, Rx<String>> debugLogMap = {};
  StreamSubscription<dynamic>? _followSubscription;

  @override
  void onInit() {
    super.onInit();
    loadFollowList();
    // 监听收藏变化事件，从搜索页返回时即时刷新
    _followSubscription =
        EventBus.instance.listen(Constant.kUpdateFollow, (_) {
      loadFollowList();
    });
  }

  @override
  void onClose() {
    _followSubscription?.cancel();
    super.onClose();
  }

  void loadFollowList() {
    followList.value = DBService.instance.getFollowList();
    checkAllLiveStatus();
  }

  Future<void> checkAllLiveStatus() async {
    isLoading.value = true;
    for (var user in followList) {
      await checkLiveStatus(user);
    }
    isLoading.value = false;
  }

  Future<void> checkLiveStatus(FollowUser user) async {
    var site = Sites.getSite(user.siteId);
    if (site == null) return;

    try {
      var status = await site.liveSite.getLiveStatus(roomId: user.roomId);
      user.liveStatus.value = status ? 2 : 1;
      if (status) {
        var detail = await site.liveSite.getRoomDetail(roomId: user.roomId);
        user.liveStartTime = detail.showTime;
      }
    } catch (e) {
      user.liveStatus.value = 0;
      Log.logPrint("检查直播状态失败: ${user.userName} - $e");
    }
  }

  void toggleRecording(FollowUser user) async {
    var session = RecordingManager.instance.getSession(user.id);
    if (session != null && session.isRecording.value) {
      await RecordingManager.instance.stopRecording(user.id);
      // 停止录音后重新加载列表
      loadFollowList();
      return;
    }

    var site = Sites.getSite(user.siteId);
    if (site == null) {
      Get.snackbar("录制失败", "不支持的平台: ${user.siteId}");
      return;
    }

    var newSession = RecordingSession(
      taskId: user.id,
      roomId: user.roomId,
      siteId: user.siteId,
      userName: user.userName,
    );

    try {
      var detail = await site.liveSite.getRoomDetail(roomId: user.roomId);
      var qualites = await site.liveSite.getPlayQualites(detail: detail);
      if (qualites.isEmpty) {
        Get.snackbar("录制失败", "未获取到可用的清晰度选项");
        return;
      }
      var playUrl = await site.liveSite.getPlayUrls(
        detail: detail,
        quality: qualites.first,
      );
      if (playUrl.urls.isEmpty) {
        Get.snackbar("录制失败", "未获取到可用的播放地址");
        return;
      }

      newSession.configure(
        getPlayUrl: () => playUrl.urls.first,
        onRefreshPlayUrl: () async {
          var newDetail = await site.liveSite.getRoomDetail(roomId: user.roomId);
          var newQualites = await site.liveSite.getPlayQualites(detail: newDetail);
          if (newQualites.isEmpty) return;
          var newUrl = await site.liveSite.getPlayUrls(
            detail: newDetail,
            quality: newQualites.first,
          );
          if (newUrl.urls.isNotEmpty) {
            playUrl.urls.first = newUrl.urls.first;
          }
        },
        getHeaders: () => playUrl.headers,
      );

      await RecordingManager.instance.startRecording(newSession);
    } catch (e) {
      Log.logPrint("开始录制失败: $e");
      Get.snackbar("录制失败", e.toString());
    }
  }

  bool isRecording(String taskId) {
    return RecordingManager.instance.isRecording(taskId);
  }

  void removeFollow(FollowUser user) async {
    var result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("取消关注"),
        content: Text("确定要取消关注「${user.userName}」吗？"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text("确定"),
          ),
        ],
      ),
    );
    if (result == true) {
      await RecordingManager.instance.stopRecording(user.id);
      DBService.instance.deleteFollow(user.id);
      followList.remove(user);
      // 通知搜索页更新收藏状态
      EventBus.instance.emit(Constant.kUpdateFollow, user.id);
    }
  }

  void pinFollow(FollowUser user) async {
    await DBService.instance.pinFollow(user.id);
    user.isPinned = true;
    loadFollowList();
  }

  void unpinFollow(FollowUser user) async {
    await DBService.instance.unpinFollow(user.id);
    user.isPinned = false;
    loadFollowList();
  }
}
