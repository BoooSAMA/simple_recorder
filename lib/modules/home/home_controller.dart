import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/services/recording_service.dart';
import 'package:simple_recorder/services/follow_export_service.dart';
import 'package:simple_recorder/services/live_notification_service.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  final followList = <FollowUser>[].obs;
  final liveList = <FollowUser>[].obs;
  final notLiveList = <FollowUser>[].obs;
  final isLoading = false.obs;

  /// 刷新加载进度 0.0~1.0
  final loadProgress = 0.0.obs;

  /// 筛选模式: 0=全部(分组) 1=直播中 2=未开播
  final filterMode = 1.obs;

  /// 筛选模式 1/2 时的过滤结果（不修改 followList）
  final filteredList = <FollowUser>[].obs;

  StreamSubscription<dynamic>? _followSubscription;
  bool _initialCheckDone = false;
  Timer? _livePoller;
  StreamSubscription<dynamic>? _pinSubscription;
  bool _firstPinCheckDone = false;

  /// 当前显示列表中的置顶直播间数量
  int get pinnedCount {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    var count = 0;
    for (final item in followList) {
      if (pinnedIds.contains(item.id)) count++;
    }
    return count;
  }

  /// 当前在直播的置顶主播数量（用于控制"一键录制"按钮显隐）
  int get pinnedLiveCount {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return 0;
    var count = 0;
    for (final user in followList) {
      if (pinnedIds.contains(user.id) && user.liveStatus.value == 2) {
        count++;
      }
    }
    return count;
  }

  @override
  void onInit() {
    super.onInit();
    loadFollowList();
    _followSubscription =
        EventBus.instance.listen(Constant.kUpdateFollow, (_) {
      loadFollowList();
    });
    _syncPoller();
    _pinSubscription =
        EventBus.instance.listen(Constant.kPinnedFollowChanged, (_) {
      _syncPoller();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onReady() {
    super.onReady();
    // 延迟首次状态检测到 onReady，避免阻塞首页渲染
    if (!_initialCheckDone && followList.isNotEmpty) {
      _initialCheckDone = true;
      checkAllLiveStatus();
    }
  }

  @override
  void onClose() {
    _followSubscription?.cancel();
    _livePoller?.cancel();
    _pinSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  void _syncPoller() {
    final settings = AppSettingsController.instance;
    final hasPinned = settings.pinnedFollowIds.isNotEmpty;
    final shouldRun = settings.liveNotificationEnabled.value && hasPinned;

    if (shouldRun && _livePoller == null) {
      _firstPinCheckDone = false;
      _livePoller = Timer.periodic(
        const Duration(minutes: 3),
        (_) => _checkPinnedLiveStatus(notify: true),
      );
      _checkPinnedLiveStatus(notify: false);
    } else if (!shouldRun && _livePoller != null) {
      _livePoller?.cancel();
      _livePoller = null;
      _firstPinCheckDone = false;
    }
  }

  void loadFollowList() {
    followList.value = DBService.instance.getFollowList();
    // 先全部初始化为"未开播"，让 UI 立即有内容
    for (final user in followList) {
      user.liveStatus.value = 1;
    }
    filterData();
    // 如果在 onReady 之后重新加载（如事件触发），需要立即检查状态
    if (_initialCheckDone) {
      checkAllLiveStatus();
    }
  }

  /// 根据筛选模式 + 置顶规则重排列表
  void filterData() {
    switch (filterMode.value) {
      case 0: // 全部：分组展示
        final live = <FollowUser>[];
        final notLive = <FollowUser>[];
        for (final user in followList) {
          if (user.liveStatus.value == 2) {
            live.add(user);
          } else {
            notLive.add(user);
          }
        }
        _sortByPin(live);
        _sortByPin(notLive);
        liveList.value = live;
        notLiveList.value = notLive;
        break;
      case 1:
        // 直播中：发布到 filteredList，不修改 followList
        final source = followList.where((u) => u.liveStatus.value == 2).toList();
        _sortByPin(source);
        filteredList.value = source;
        break;
      case 2:
        // 未开播：发布到 filteredList，不修改 followList
        final source = followList.where((u) => u.liveStatus.value != 2).toList();
        _sortByPin(source);
        filteredList.value = source;
        break;
    }
  }

  void _sortByPin(List<FollowUser> items) {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    items.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });
  }

  Future<void> _checkPinnedLiveStatus({bool notify = false}) async {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return;

    final settings = AppSettingsController.instance;
    if (!settings.liveNotificationEnabled.value && notify) return;

    for (final user in followList) {
      if (!pinnedIds.contains(user.id)) continue;

      try {
        var site = Sites.getSite(user.siteId);
        if (site == null) continue;

        final wasLive = user.liveStatus.value == 2;
        final isLive =
            await site.liveSite.getLiveStatus(roomId: user.roomId);
        user.liveStatus.value = isLive ? 2 : 1;

        if (!wasLive && isLive && notify && _firstPinCheckDone) {
          await LiveNotificationService.instance.notifyLiveStart(user);
        }
        if (!isLive) {
          LiveNotificationService.instance.clearNotified(user.id);
        }
      } catch (e) {
        Log.logPrint("检测 pin 主播状态失败: ${user.userName} - $e");
        user.liveStatus.value = 0;
      }
    }
    _firstPinCheckDone = true;
    filterData();
  }

  void setFilterMode(int mode) {
    filterMode.value = mode;
    filterData();
  }

  /// 高并发检查所有直播间直播状态（流式并发，始终保持 N 个请求在飞）
  Future<void> checkAllLiveStatus() async {
    if (followList.isEmpty) return;

    isLoading.value = true;
    loadProgress.value = 0.0;

    final users = followList.toList();
    final liveIds = <String>{};
    int completed = 0;
    const maxConcurrency = 20;

    // 不预重置状态 — 保持旧状态直到新结果返回，避免闪烁
    for (final user in users) {
      if (user.liveStatus.value == 0) {
        user.liveStatus.value = 1;
      }
    }

    int cursor = 0;
    final futures = <Future<void>>[];

    // 流式并发：每个 worker 处理一个后自动取下一个，始终保持 maxConcurrency 个在飞
    Future<void> runWorker() async {
      while (cursor < users.length) {
        final user = users[cursor++];
        try {
          var site = Sites.getSite(user.siteId);
          if (site == null) continue;
          var isLive =
              await site.liveSite.getLiveStatus(roomId: user.roomId);
          user.liveStatus.value = isLive ? 2 : 1;
          if (isLive) {
            liveIds.add(user.id);
          }
        } catch (e) {
          Log.logPrint("检查直播状态失败: ${user.userName} - $e");
          user.liveStatus.value = 0;
        } finally {
          completed++;
          loadProgress.value = completed / users.length;
          _syncLists(users, liveIds);
        }
      }
    }

    // 启动 maxConcurrency 个并行 worker
    for (var i = 0; i < maxConcurrency; i++) {
      futures.add(runWorker());
    }

    await Future.wait(futures);

    filterData();
    isLoading.value = false;
  }

  void _syncLists(List<FollowUser> allUsers, Set<String> liveIds) {
    final live = <FollowUser>[];
    final notLive = <FollowUser>[];
    for (final user in allUsers) {
      if (liveIds.contains(user.id)) {
        live.add(user);
      } else {
        notLive.add(user);
      }
    }
    _sortByPin(live);
    _sortByPin(notLive);
    liveList.value = live;
    notLiveList.value = notLive;

    // 如果当前在筛选模式，同步更新 filteredList
    if (filterMode.value == 1) {
      filteredList.value = live;
    } else if (filterMode.value == 2) {
      filteredList.value = notLive;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPoller();
      _checkPinnedLiveStatus(notify: true);
    } else if (state == AppLifecycleState.paused) {
      if (RecordingManager.instance.activeSessions.isEmpty) {
        _livePoller?.cancel();
        _livePoller = null;
      }
    }
  }

  /// 切换录制状态（开始录制）
  void toggleRecording(FollowUser user) async {
    var session = RecordingManager.instance.getSession(user.id);
    if (session != null && session.isRecording.value) {
      // 已在录制中，通过 stopRecording 或 cancelRecording 处理
      return;
    }

    if (user.liveStatus.value == 0) {
      Get.snackbar(
        "录制失败",
        "直播状态未知，请刷新后再试",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (user.liveStatus.value != 2) {
      Get.snackbar(
        "录制失败",
        "主播未开播，无法录制",
        snackPosition: SnackPosition.BOTTOM,
      );
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

  /// 一键录制所有正在直播的置顶主播（顺序启动，避免高并发）
  Future<void> startAllPinnedRecordings() async {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return;

    final pinLives = followList
        .where((u) => pinnedIds.contains(u.id) && u.liveStatus.value == 2)
        .toList();

    if (pinLives.isEmpty) {
      Get.snackbar("提示", "没有正在直播的置顶主播",
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isLoading.value = true;
    var started = 0;
    var skipped = 0;

    for (var i = 0; i < pinLives.length; i++) {
      loadProgress.value = (i + 1) / pinLives.length;
      final user = pinLives[i];

      // 跳过已在录制中的
      var existing = RecordingManager.instance.getSession(user.id);
      if (existing != null && existing.isRecording.value) {
        started++;
        continue;
      }

      var site = Sites.getSite(user.siteId);
      if (site == null) {
        Log.logPrint("一键录制跳过: 不支持的平台 ${user.siteId}");
        skipped++;
        continue;
      }

      try {
        var newSession = RecordingSession(
          taskId: user.id,
          roomId: user.roomId,
          siteId: user.siteId,
          userName: user.userName,
        );

        var detail = await site.liveSite.getRoomDetail(roomId: user.roomId);
        var qualites = await site.liveSite.getPlayQualites(detail: detail);
        if (qualites.isEmpty) {
          Log.logPrint("一键录制跳过(${user.userName}): 无清晰度选项");
          skipped++;
          continue;
        }

        var playUrl = await site.liveSite.getPlayUrls(
          detail: detail,
          quality: qualites.first,
        );
        if (playUrl.urls.isEmpty) {
          Log.logPrint("一键录制跳过(${user.userName}): 无播放地址");
          skipped++;
          continue;
        }

        newSession.configure(
          getPlayUrl: () => playUrl.urls.first,
          onRefreshPlayUrl: () async {
            var newDetail =
                await site.liveSite.getRoomDetail(roomId: user.roomId);
            var newQualites =
                await site.liveSite.getPlayQualites(detail: newDetail);
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
        started++;
      } catch (e) {
        Log.logPrint("一键录制失败(${user.userName}): $e");
        skipped++;
      }
    }

    isLoading.value = false;
    loadProgress.value = 0;

    Get.snackbar("一键录制完成",
        "成功启动: $started  |  跳过/失败: $skipped",
        snackPosition: SnackPosition.BOTTOM);
  }

  /// 停止录制（保存文件）
  void stopRecording(FollowUser user) async {
    var fileInfo = await RecordingManager.instance.stopRecording(user.id);
    if (fileInfo != null) {
      Get.snackbar(
        "录制已停止",
        "文件名: ${fileInfo['fileName']}\n"
        "大小: ${fileInfo['fileSize']}\n"
        "路径: ${fileInfo['path']}",
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 4),
        maxWidth: Get.width * 0.9,
      );
    } else {
      Get.snackbar(
        "录制已停止",
        "文件已保存",
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// 取消录制（删除文件）
  void cancelRecording(FollowUser user) async {
    var confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("取消录制"),
        content: const Text("确定要取消录制吗？已录制的文件将被删除。"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("继续录制"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text("取消录制", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await RecordingManager.instance.cancelRecording(user.id);
    Get.snackbar(
      "录制已取消",
      "文件已删除",
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
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
      AppSettingsController.instance.toggleFollowPin(user.id);
      followList.remove(user);
      EventBus.instance.emit(Constant.kUpdateFollow, user.id);
    }
  }

  /// 导出关注数据
  void exportData() {
    FollowExportService.exportFollowData();
  }

  /// 导入关注数据
  void importData() {
    FollowExportService.importFollowData();
  }
}
