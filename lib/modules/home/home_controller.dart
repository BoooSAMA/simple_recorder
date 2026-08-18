import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/app/sites_fixed.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_recorder/services/local_storage_service.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/services/recording_service.dart';
import 'package:simple_recorder/services/live_notification_service.dart';

/// 续录队列条目
class _ReRecordTask {
  final String userId;
  final String roomId;
  final String siteId;
  final String userName;
  int retriesLeft;
  Timer? timer;

  _ReRecordTask({
    required this.userId,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.retriesLeft,
  });
}

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
  bool _backgroundCheckRunning = false;
  StreamSubscription<RecordingSession>? _reRecordSub;
  final _reRecordQueue = <_ReRecordTask>[];

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

  /// 当前正在录制的置顶直播间数量（用于"一键结束"按钮显隐）
  int get pinnedRecordingCount {
    final _ = RecordingManager.instance.activeCount.value; // 响应式触发
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return 0;
    var count = 0;
    for (final user in followList) {
      if (!pinnedIds.contains(user.id)) continue;
      if (RecordingManager.instance.isRecording(user.id)) count++;
    }
    return count;
  }

  /// 可启动录制的置顶直播数量（已开播 + 未在录制，用于"一键录制"按钮显隐）
  int get pinnedReadyCount {
    final _ = RecordingManager.instance.activeCount.value; // 响应式触发
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return 0;
    var count = 0;
    for (final user in followList) {
      if (!pinnedIds.contains(user.id) || user.liveStatus.value != 2) continue;
      if (!RecordingManager.instance.isRecording(user.id)) count++;
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
    _reRecordSub = RecordingManager.instance.onSessionEnded.stream.listen(_onSessionEnded);
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
    _reRecordSub?.cancel();
    _cancelAllReRecord();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  void _syncPoller() {
    final settings = AppSettingsController.instance;
    final hasPinned = settings.pinnedFollowIds.isNotEmpty;
    final wantNonPinned = settings.backgroundRefreshNonPinned.value ||
        settings.notifyNonPinnedLive.value;
    // 有置顶主播，或开启了非置顶主播的后台刷新/通知时才运行轮询
    final shouldRun =
        settings.liveNotificationEnabled.value && (hasPinned || wantNonPinned);

    if (shouldRun && _livePoller == null) {
      _firstPinCheckDone = false;
      _livePoller = Timer.periodic(
        Duration(minutes: settings.livePollInterval.value),
        (_) => _checkBackgroundLiveStatus(notify: true),
      );
      _checkBackgroundLiveStatus(notify: false);
      // 保活：防止后台进程被杀死
      LiveNotificationService.instance.acquireKeepAlive();
    } else if (!shouldRun && _livePoller != null) {
      _livePoller?.cancel();
      _livePoller = null;
      _firstPinCheckDone = false;
      LiveNotificationService.instance.releaseKeepAlive();
    }
  }

  void loadFollowList() {
    followList.value = DBService.instance.getFollowList();
    // 先恢复上次检测的缓存状态，让 UI 立即有内容（无缓存的置"未开播"）
    _restoreLiveStatusCache();
    for (final user in followList) {
      if (user.liveStatus.value == 0) {
        user.liveStatus.value = 1;
      }
    }
    filterData();
    // 如果在 onReady 之后重新加载（如事件触发），需要立即检查状态
    if (_initialCheckDone) {
      checkAllLiveStatus();
    }
  }

  /// 保存直播状态缓存（settings box，供下次启动立即恢复）
  void _saveLiveStatusCache() {
    final cache = <String, int>{};
    for (final user in followList) {
      final status = user.liveStatus.value;
      if (status == 0) continue; // 未知（检测失败）不覆盖旧缓存
      cache[user.id] = status;
    }
    LocalStorageService.instance.setValue("last_live_status", cache);
  }

  /// 从缓存恢复上次检测的直播状态
  void _restoreLiveStatusCache() {
    final raw = LocalStorageService.instance.getValue("last_live_status");
    if (raw is! Map) return;
    for (final user in followList) {
      final status = raw[user.id];
      if (status is int && (status == 1 || status == 2)) {
        user.liveStatus.value = status;
      }
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

  // ========== 直播恢复自动续录 ==========

  void _onSessionEnded(RecordingSession session) {
    final settings = AppSettingsController.instance;
    if (!settings.autoReRecordEnabled.value) return;
    if (session.isUserStopped) {
      Log.logPrint("用户主动停止，不触发续录: ${session.userName}");
      return;
    }
    // 避免重复加入
    if (_reRecordQueue.any((t) => t.userId == session.taskId)) return;
    // 确认该用户仍在关注列表
    final user = followList.firstWhereOrNull((u) => u.id == session.taskId);
    if (user == null) return;

    final task = _ReRecordTask(
      userId: session.taskId,
      roomId: session.roomId,
      siteId: session.siteId,
      userName: session.userName,
      retriesLeft: settings.autoReRecordMaxRetries.value,
    );
    _reRecordQueue.add(task);
    Log.logPrint("加入续录队列: ${session.userName}, "
        "${settings.autoReRecordDelayMinutes}分钟后第1次检测, "
        "共${settings.autoReRecordMaxRetries.value}次");

    _scheduleReRecordCheck(task);
  }

  void _scheduleReRecordCheck(_ReRecordTask task) {
    final delay = AppSettingsController.instance.autoReRecordDelayMinutes.value;
    task.timer?.cancel();
    task.timer = Timer(Duration(minutes: delay), () => _processReRecordTask(task));
  }

  Future<void> _processReRecordTask(_ReRecordTask task) async {
    // 用户已不在关注列表中
    if (!followList.any((u) => u.id == task.userId)) {
      _removeFromReRecordQueue(task);
      Log.logPrint("续录取消: 用户已不在关注列表: ${task.userName}");
      return;
    }

    // 用户已在录制中（可能是手动启动的）
    if (RecordingManager.instance.isRecording(task.userId)) {
      _removeFromReRecordQueue(task);
      Log.logPrint("续录取消: 用户已在录制中: ${task.userName}");
      return;
    }

    try {
      final site = Sites.getSite(task.siteId);
      if (site == null) {
        _removeFromReRecordQueue(task);
        return;
      }

      final isLive = await site.liveSite.getLiveStatus(roomId: task.roomId);
      if (isLive) {
        Log.logPrint("续录: 检测到主播重新开播，开始录制: ${task.userName}");
        final user = followList.firstWhereOrNull((u) => u.id == task.userId);
        if (user != null) {
          // _autoStartRecording 内部检查 liveStatus == 2，必须在调用前设置
          user.liveStatus.value = 2;
          await _autoStartRecording(user);
          filterData();
        }
        _removeFromReRecordQueue(task);
        return;
      }
    } catch (e) {
      Log.logPrint("续录检测失败: ${task.userName} - $e");
    }

    // 未检测到开播
    task.retriesLeft--;
    if (task.retriesLeft <= 0) {
      Log.logPrint("续录放弃: 已达最大检测次数: ${task.userName}");
      _removeFromReRecordQueue(task);
    } else {
      final settings = AppSettingsController.instance;
      final attemptIndex = settings.autoReRecordMaxRetries.value - task.retriesLeft + 1;
      Log.logPrint("续录: ${task.userName} 未开播，"
          "${settings.autoReRecordDelayMinutes}分钟后第$attemptIndex次检测");
      _scheduleReRecordCheck(task);
    }
  }

  void _removeFromReRecordQueue(_ReRecordTask task) {
    task.timer?.cancel();
    _reRecordQueue.remove(task);
  }

  void _cancelAllReRecord() {
    for (final task in _reRecordQueue) {
      task.timer?.cancel();
    }
    _reRecordQueue.clear();
  }

  Future<void> _checkBackgroundLiveStatus({bool notify = false}) async {
    // 防止上次检测未完成时本次 tick 重叠执行
    if (_backgroundCheckRunning) return;
    _backgroundCheckRunning = true;

    try {
      final settings = AppSettingsController.instance;
      if (!settings.liveNotificationEnabled.value && notify) return;

      final pinnedIds = settings.pinnedFollowIds;
      final wantNonPinned = settings.backgroundRefreshNonPinned.value ||
          settings.notifyNonPinnedLive.value;

      final pinnedUsers = <FollowUser>[];
      final nonPinnedUsers = <FollowUser>[];
      for (final user in followList) {
        if (pinnedIds.contains(user.id)) {
          pinnedUsers.add(user);
        } else if (wantNonPinned) {
          nonPinnedUsers.add(user);
        }
      }
      if (pinnedUsers.isEmpty && nonPinnedUsers.isEmpty) return;

      // B站用户统一批量检测（一次请求查多个房间），其余按原逻辑检测
      final allUsers = [...pinnedUsers, ...nonPinnedUsers];
      final biliUsers = allUsers
          .where((u) => u.siteId == Constant.kBiliBili)
          .toList();
      final restPinned = allUsers
          .where((u) =>
              u.siteId != Constant.kBiliBili && pinnedIds.contains(u.id))
          .toList();
      final restNonPinned = allUsers
          .where((u) =>
              u.siteId != Constant.kBiliBili && !pinnedIds.contains(u.id))
          .toList();

      final tasks = <Future<void>>[];
      if (biliUsers.isNotEmpty) {
        tasks.add(_checkBiliUsersBackground(biliUsers, notify: notify));
      }

      for (final user in restPinned) {
        tasks.add(_checkBackgroundUser(user, notify: notify, isPinned: true));
      }

      // 非置顶主播数量可能较多，按并发上限分池检测
      if (restNonPinned.isNotEmpty) {
        final maxConcurrency =
            settings.liveCheckConcurrency.value.clamp(1, 50).toInt();
        final queue = List<FollowUser>.from(restNonPinned);
        Future<void> worker() async {
          while (queue.isNotEmpty) {
            final user = queue.removeAt(0);
            await _checkBackgroundUser(
                user, notify: notify, isPinned: false);
          }
        }

        final workerCount =
            maxConcurrency < queue.length ? maxConcurrency : queue.length;
        for (var i = 0; i < workerCount; i++) {
          tasks.add(worker());
        }
      }

      await Future.wait(tasks);
    } finally {
      _backgroundCheckRunning = false;
      _firstPinCheckDone = true;
      filterData();
      _saveLiveStatusCache();
    }
  }

  /// B站批量后台检测：一次批量请求；失败时降级为逐个检测
  Future<void> _checkBiliUsersBackground(
    List<FollowUser> users, {
    required bool notify,
  }) async {
    final settings = AppSettingsController.instance;
    try {
      final result = await bilibiliGetLiveStatusBatch(
        users.map((u) => u.roomId).toList(),
      );
      if (result == null) {
        // 批量不可用 → 降级逐个
        for (final user in users) {
          await _checkBackgroundUser(
            user,
            notify: notify,
            isPinned: settings.pinnedFollowIds.contains(user.id),
          );
        }
        return;
      }
      for (final user in users) {
        await _applyBackgroundStatus(
          user,
          result[user.roomId] ?? false,
          notify: notify,
          isPinned: settings.pinnedFollowIds.contains(user.id),
        );
      }
    } catch (e) {
      Log.logPrint("B站批量检测失败，降级逐个检测: $e");
      for (final user in users) {
        await _checkBackgroundUser(
          user,
          notify: notify,
          isPinned: settings.pinnedFollowIds.contains(user.id),
        );
      }
    }
  }

  /// 后台轮询单个主播：刷新状态；开播时按策略通知/自动录制
  Future<void> _checkBackgroundUser(
    FollowUser user, {
    required bool notify,
    required bool isPinned,
  }) async {
    try {
      var site = Sites.getSite(user.siteId);
      if (site == null) return;

      final isLive = await site.liveSite.getLiveStatus(roomId: user.roomId);
      await _applyBackgroundStatus(
          user, isLive, notify: notify, isPinned: isPinned);
    } catch (e) {
      Log.logPrint("检测直播状态失败: ${user.userName} - $e");
      user.liveStatus.value = 0;
    }
  }

  /// 应用后台检测结果：更新状态 + 开播通知/自动录制 + 下播自动停录
  Future<void> _applyBackgroundStatus(
    FollowUser user,
    bool isLive, {
    required bool notify,
    required bool isPinned,
  }) async {
    final settings = AppSettingsController.instance;

    final wasLive = user.liveStatus.value == 2;
    user.liveStatus.value = isLive ? 2 : 1;

    // 首次检测（app 启动/设置变更后）不通知，避免误报
    if (!wasLive && isLive && notify && _firstPinCheckDone) {
      if (isPinned) {
        await LiveNotificationService.instance.notifyLiveStart(user);
        // 自动录制：置顶主播开播时自动开始录制
        if (settings.autoRecordPinned.value) {
          await _autoStartRecording(user);
        }
      } else if (settings.notifyNonPinnedLive.value) {
        // 非置顶主播：仅当"非置顶开播通知"开启时通知
        await LiveNotificationService.instance.notifyLiveStart(user);
      }
    }
    if (!isLive) {
      LiveNotificationService.instance.clearNotified(user.id);
      // 直播已结束：若正在录制则自动停止
      if (RecordingManager.instance.isRecording(user.id)) {
        Log.logPrint("检测到直播已结束，自动停止录制: ${user.userName}");
        await RecordingManager.instance.stopRecording(user.id);
      }
    }
  }

  void setFilterMode(int mode) {
    filterMode.value = mode;
    filterData();
  }

  /// 分批检测所有直播间直播状态：Pinned 用户优先，其余延迟错峰
  Future<void> checkAllLiveStatus() async {
    if (followList.isEmpty) return;

    // 每次刷新先清理停滞 session，保证录制计数实时准确
    RecordingManager.instance.cleanupStaleSessions();

    isLoading.value = true;
    loadProgress.value = 0.0;

    final allUsers = followList.toList();
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    final liveIds = <String>{};
    int completed = 0;
    final maxConcurrency = AppSettingsController.instance.liveCheckConcurrency.value;
    final total = allUsers.length;

    // 不预重置状态 — 保持旧状态直到新结果返回，避免闪烁
    for (final user in allUsers) {
      if (user.liveStatus.value == 0) {
        user.liveStatus.value = 1;
      }
    }

    // ---- B站批量检测：一次请求查最多 50 个房间，N 个请求合并为 1-2 个 ----
    final biliUsers = allUsers
        .where((u) => u.siteId == Constant.kBiliBili)
        .toList();
    final restUsers = allUsers
        .where((u) => u.siteId != Constant.kBiliBili)
        .toList();

    // 批量结果回填：与 runWorker 中的处理完全一致（状态/停录/计数/进度/同步）
    Future<void> applyBatchResult(FollowUser user, bool isLive) async {
      user.liveStatus.value = isLive ? 2 : 1;
      if (isLive) {
        liveIds.add(user.id);
      } else {
        // 非直播状态：若正在录制则自动停止
        if (RecordingManager.instance.isRecording(user.id)) {
          Log.logPrint("检测到直播已结束，自动停止录制: ${user.userName}");
          await RecordingManager.instance.stopRecording(user.id);
        }
      }
      completed++;
      loadProgress.value = completed / total;
      _syncLists(allUsers, liveIds);
    }

    if (biliUsers.isNotEmpty) {
      try {
        final result = await bilibiliGetLiveStatusBatch(
          biliUsers.map((u) => u.roomId).toList(),
        );
        if (result != null) {
          for (final user in biliUsers) {
            await applyBatchResult(user, result[user.roomId] ?? false);
          }
        } else {
          // 批量接口不可用 → 降级为逐个检测
          restUsers.addAll(biliUsers);
        }
      } catch (e) {
        Log.logPrint("B站批量检测失败，降级逐个检测: $e");
        restUsers.addAll(biliUsers);
      }
    }

    // 共享任务队列，支持分批动态追加
    final queue = <FollowUser>[];

    Future<void> runWorker() async {
      while (true) {
        FollowUser? user;
        if (queue.isNotEmpty) {
          user = queue.removeAt(0);
        }
        if (user == null) break;

        try {
          var site = Sites.getSite(user.siteId);
          if (site == null) continue;
          var isLive =
              await site.liveSite.getLiveStatus(roomId: user.roomId);
          user.liveStatus.value = isLive ? 2 : 1;
          if (isLive) {
            liveIds.add(user.id);
          } else {
            // 非直播状态：若正在录制则自动停止
            if (RecordingManager.instance.isRecording(user.id)) {
              Log.logPrint("检测到直播已结束，自动停止录制: ${user.userName}");
              await RecordingManager.instance.stopRecording(user.id);
            }
          }
        } catch (e) {
          Log.logPrint("检查直播状态失败: ${user.userName} - $e");
          user.liveStatus.value = 0;
        } finally {
          completed++;
          loadProgress.value = completed / total;
          _syncLists(allUsers, liveIds);
        }
      }
    }

    Future<void> drainQueue() async {
      if (queue.isEmpty) return;
      final workerCount = maxConcurrency < queue.length ? maxConcurrency : queue.length;
      final futures = <Future<void>>[];
      for (var i = 0; i < workerCount; i++) {
        futures.add(runWorker());
      }
      await Future.wait(futures);
    }

    if (pinnedIds.isNotEmpty) {
      // ---- 第一批：Pinned 用户优先检测 ----
      for (final user in allUsers) {
        if (pinnedIds.contains(user.id)) {
          queue.add(user);
        }
      }
      await drainQueue();

      // ---- 第二批：其余用户延迟错峰 ----
      if (completed < total) {
        await Future.delayed(const Duration(seconds: 2));
        for (final user in allUsers) {
          if (!pinnedIds.contains(user.id)) {
            queue.add(user);
          }
        }
        await drainQueue();
      }
    } else {
      // 没有 Pinned 用户，直接全部检测（无延迟）
      queue.addAll(allUsers);
      await drainQueue();
    }

    filterData();
    _saveLiveStatusCache();
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
      _checkBackgroundLiveStatus(notify: true);
    }
  }

  /// 获取直播间开播时长信息
  Future<void> getLiveDuration(FollowUser user) async {
    var site = Sites.getSite(user.siteId);
    if (site == null) {
      Get.snackbar("获取失败", "不支持的平台: ${user.siteId}",
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      var detail = await site.liveSite.getRoomDetail(roomId: user.roomId);
      if (!detail.status) {
        Get.snackbar("未开播", "${user.userName} 当前未在直播",
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      if (detail.showTime != null && detail.showTime!.isNotEmpty) {
        try {
          int startTimeStamp = int.parse(detail.showTime!);
          var startDt =
              DateTime.fromMillisecondsSinceEpoch(startTimeStamp * 1000);
          var timeStr =
              '${startDt.hour.toString().padLeft(2, '0')}:${startDt.minute.toString().padLeft(2, '0')}:${startDt.second.toString().padLeft(2, '0')}';

          int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          int diff = currentTimeStamp - startTimeStamp;
          if (diff > 0) {
            int hours = diff ~/ 3600;
            int minutes = (diff % 3600) ~/ 60;
            int seconds = diff % 60;
            Get.snackbar(
              "直播信息 · ${user.userName}",
              "开播时间: $timeStr\n已播时长: $hours小时$minutes分$seconds秒",
              snackPosition: SnackPosition.BOTTOM,
              duration: const Duration(seconds: 5),
            );
            return;
          }
        } catch (_) {}
      }

      Get.snackbar(
        "直播信息 · ${user.userName}",
        "该平台暂不支持查询开播时长",
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar("获取失败", e.toString(),
          snackPosition: SnackPosition.BOTTOM);
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

  /// 静默自动录制（用于自动录制功能，不弹 SnackBar，仅记日志）
  Future<void> _autoStartRecording(FollowUser user) async {
    var session = RecordingManager.instance.getSession(user.id);
    if (session != null && session.isRecording.value) return;

    if (user.liveStatus.value != 2) return;

    var site = Sites.getSite(user.siteId);
    if (site == null) {
      Log.logPrint("自动录制失败: 不支持的平台 ${user.siteId}");
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
      var qualities = await site.liveSite.getPlayQualites(detail: detail);
      if (qualities.isEmpty) {
        Log.logPrint("自动录制失败: 未获取到清晰度选项: ${user.userName}");
        return;
      }
      var playUrl = await site.liveSite.getPlayUrls(
        detail: detail,
        quality: qualities.first,
      );
      if (playUrl.urls.isEmpty) {
        Log.logPrint("自动录制失败: 未获取到播放地址: ${user.userName}");
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
      Log.logPrint("自动录制已启动: ${user.userName}");
    } catch (e) {
      Log.logPrint("自动录制失败: ${user.userName} - $e");
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

  /// 一键结束所有置顶直播的录制（顺序停止，不影响自动解包）
  Future<void> stopAllPinnedRecordings() async {
    final pinnedIds = AppSettingsController.instance.pinnedFollowIds;
    if (pinnedIds.isEmpty) return;

    final pinRecording = <FollowUser>[];
    for (final user in followList) {
      if (!pinnedIds.contains(user.id)) continue;
      if (RecordingManager.instance.isRecording(user.id)) {
        pinRecording.add(user);
      }
    }

    if (pinRecording.isEmpty) {
      Get.snackbar("提示", "没有正在录制的置顶直播间",
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isLoading.value = true;
    var stopped = 0;

    for (var i = 0; i < pinRecording.length; i++) {
      loadProgress.value = (i + 1) / pinRecording.length;
      final user = pinRecording[i];
      await RecordingManager.instance.stopRecording(user.id);
      stopped++;
    }

    isLoading.value = false;
    loadProgress.value = 0;

    Get.snackbar("一键结束完成",
        "已停止 $stopped 个录制",
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

}
