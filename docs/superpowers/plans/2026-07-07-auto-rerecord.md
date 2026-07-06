# 直播恢复自动续录 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 录制因直播结束自动停止后，分钟级定时检测主播是否重新开播，自动恢复录制。

**Architecture:** 三层防御（FFmpeg reconnect → 秒级重试 → 分钟级续录）。续录逻辑由 HomeController 管理，通过 RecordingManager.onSessionEnded 事件流监听 session 结束，使用独立 Timer 逐个检测。

**Tech Stack:** GetX, Hive (local_storage_service), Dart async

---

### Task 1: RecordingSession — 暴露 isUserStopped

**Files:**
- Modify: `lib/services/recording_service.dart:409`

- [ ] **添加 isUserStopped getter**

在 `bool _stopRequested = false;` 之后添加：

```dart
/// 是否为用户主动停止（而非直播结束/重试耗尽导致的自然结束）
bool get isUserStopped => _stopRequested;
```

---

### Task 2: RecordingManager — 添加 onSessionEnded 事件流

**Files:**
- Modify: `lib/services/recording_manager.dart:1-15`

- [ ] **添加 StreamController 导入和字段**

在文件顶部导入 `dart:async`（已存在），在类字段区添加：

```dart
/// session 自然结束时广播事件，供 HomeController 监听续录
final onSessionEnded = StreamController<RecordingSession>.broadcast();
```

- [ ] **在 onFinished 回调中发送事件**

修改 L49-52 的 `session.onFinished` 回调：

```dart
session.onFinished = () {
  activeSessions.remove(session);
  activeCount.value = activeSessions.length;
  onSessionEnded.add(session);  // 通知外部 session 已结束
};
```

- [ ] **在 onClose 中关闭 StreamController**

```dart
@override
void onClose() {
  stopAll();
  onSessionEnded.close();
  super.onClose();
}
```

---

### Task 3: AppSettingsController — 添加 3 个设置项

**Files:**
- Modify: `lib/app/controller/app_settings_controller.dart`

- [ ] **添加字段**

在 `autoSliceIntervalMinutes` 之后（L32）添加：

```dart
/// 直播恢复自动续录
final autoReRecordEnabled = false.obs;
final autoReRecordDelayMinutes = 5.obs;
final autoReRecordMaxRetries = 3.obs;
```

- [ ] **在 loadSettings() 中加载**

在 `autoSliceIntervalMinutes` 加载之后（L74）添加：

```dart
autoReRecordEnabled.value = LocalStorageService.instance
    .getValue("auto_rerecord_enabled", false);
autoReRecordDelayMinutes.value = LocalStorageService.instance
    .getValue("auto_rerecord_delay", 5);
autoReRecordMaxRetries.value = LocalStorageService.instance
    .getValue("auto_rerecord_max_retries", 3);
```

- [ ] **添加 setter 方法**

在 `setAutoSliceIntervalMinutes` 之后（L188）添加：

```dart
void setAutoReRecordEnabled(bool value) {
  autoReRecordEnabled.value = value;
  LocalStorageService.instance.setValue("auto_rerecord_enabled", value);
}

void setAutoReRecordDelayMinutes(int minutes) {
  final clamped = minutes.clamp(1, 30);
  autoReRecordDelayMinutes.value = clamped;
  LocalStorageService.instance.setValue("auto_rerecord_delay", clamped);
}

void setAutoReRecordMaxRetries(int retries) {
  final clamped = retries.clamp(1, 10);
  autoReRecordMaxRetries.value = clamped;
  LocalStorageService.instance.setValue("auto_rerecord_max_retries", clamped);
}
```

---

### Task 4: HomeController — 续录队列逻辑

**Files:**
- Modify: `lib/modules/home/home_controller.dart`

- [ ] **在类顶部添加续录队列结构和字段**

在 `_firstPinCheckDone`（L34）之后添加：

```dart
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
```

在 `_pinSubscription`（L34）之后添加：

```dart
StreamSubscription<RecordingSession>? _reRecordSub;
final _reRecordQueue = <_ReRecordTask>[];
```

- [ ] **在 onInit 中订阅 onSessionEnded**

在 `onInit` 的 `_pinSubscription` 订阅之后添加：

```dart
_reRecordSub = RecordingManager.instance.onSessionEnded.listen(_onSessionEnded);
```

- [ ] **在 onClose 中清理**

```dart
@override
void onClose() {
  _followSubscription?.cancel();
  _livePoller?.cancel();
  _pinSubscription?.cancel();
  _reRecordSub?.cancel();    // 新增
  _cancelAllReRecord();      // 新增
  WidgetsBinding.instance.removeObserver(this);
  super.onClose();
}
```

- [ ] **添加 _onSessionEnded 回调方法**

在 `_checkPinnedLiveStatus` 之前（L200）添加：

```dart
/// session 自然结束时触发续录判断
void _onSessionEnded(RecordingSession session) {
  final settings = AppSettingsController.instance;
  if (!settings.autoReRecordEnabled.value) return;
  if (session.isUserStopped) {
    Log.logPrint("用户主动停止，不触发续录: ${session.userName}");
    return;
  }
  // 避免重复加入（已在该队列中则跳过）
  if (_reRecordQueue.any((t) => t.userId == session.taskId)) return;
  // 检查该用户仍在关注列表
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
```

- [ ] **添加 _scheduleReRecordCheck 和 _processReRecord**

```dart
/// 为续录任务设定定时器（延迟 delayMinutes 分钟后检测）
void _scheduleReRecordCheck(_ReRecordTask task) {
  final delay = AppSettingsController.instance.autoReRecordDelayMinutes.value;
  task.timer?.cancel();
  task.timer = Timer(Duration(minutes: delay), () => _processReRecordTask(task));
}

/// 执行一次续录检测
Future<void> _processReRecordTask(_ReRecordTask task) async {
  // 用户已不在关注列表中
  if (followList.any((u) => u.id == task.userId) == false) {
    _removeFromReRecordQueue(task);
    Log.logPrint("续录取消: 用户已不在关注列表: ${task.userName}");
    return;
  }

  // 如果用户已经在录制中（可能是手动启动的），移除续录任务
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
      // 从关注列表中找到该用户，复用 _autoStartRecording
      // 注意: _autoStartRecording 内部检查 liveStatus == 2，必须在调用前设置
      final user = followList.firstWhereOrNull((u) => u.id == task.userId);
      if (user != null) {
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
    Log.logPrint("续录: ${task.userName} 未开播，"
        "${settings.autoReRecordDelayMinutes}分钟后第"
        "${settings.autoReRecordMaxRetries.value - task.retriesLeft + 1}次检测");
    _scheduleReRecordCheck(task);
  }
}

/// 从续录队列移除并取消定时器
void _removeFromReRecordQueue(_ReRecordTask task) {
  task.timer?.cancel();
  _reRecordQueue.remove(task);
}

/// 清理所有续录任务
void _cancelAllReRecord() {
  for (final task in _reRecordQueue) {
    task.timer?.cancel();
  }
  _reRecordQueue.clear();
}
```

- [ ] **同步更新 filterData 方法中的续录队列状态（可选优化）**

当用户手动停止录制时，`RecordingManager.stopRecording()` → `session.stop()` → `_stopRequested=true` → `isUserStopped=true` → 在 `_onSessionEnded` 回调中会自动跳过续录。

但还有一种情况：用户在设置页关闭了自动续录开关，此时需要清理队列。在 `onInit` 中监听设置变化：

不添加这个，因为开关变化不频繁，而且队列中的任务最多也就存在几十分钟。如果非要处理，可以加个 Settings 监听。

---

### Task 5: SettingsPage — 续录配置 UI

**Files:**
- Modify: `lib/modules/settings/settings_page.dart`
- Reference: `lib/widgets/settings/settings_number.dart`

- [ ] **在"自动切片录制"区域之后、"存储"区域之前添加续录配置**

在 `autoSliceIntervalMinutes` 的 `Obx` 区块之后（L92 的 `]),` 之后）添加：

```dart
const Divider(height: 1, indent: 16),
Obx(() => SwitchListTile(
  title: const Text("直播恢复自动续录"),
  subtitle: const Text("直播结束后自动检测主播是否重新开播并恢复录制"),
  value: controller.autoReRecordEnabled.value,
  onChanged: (v) => controller.setAutoReRecordEnabled(v),
)),
Obx(() {
  var enabled = controller.autoReRecordEnabled.value;
  var delay = controller.autoReRecordDelayMinutes.value;
  return Opacity(
    opacity: enabled ? 1.0 : 0.4,
    child: AbsorbPointer(
      absorbing: !enabled,
      child: SettingsNumber(
        title: "检测间隔",
        value: delay,
        min: 1,
        max: 30,
        step: 1,
        unit: " 分钟",
        displayValue: "$delay 分钟",
        subtitle: "直播断开后多久检测一次 (1~30)",
        onChanged: enabled
            ? (v) => controller.setAutoReRecordDelayMinutes(v)
            : null,
      ),
    ),
  );
}),
Obx(() {
  var enabled = controller.autoReRecordEnabled.value;
  var retries = controller.autoReRecordMaxRetries.value;
  return Opacity(
    opacity: enabled ? 1.0 : 0.4,
    child: AbsorbPointer(
      absorbing: !enabled,
      child: SettingsNumber(
        title: "最大检测次数",
        value: retries,
        min: 1,
        max: 10,
        step: 1,
        unit: " 次",
        displayValue: "$retries 次",
        subtitle: "最多检测几次后放弃 (1~10)",
        onChanged: enabled
            ? (v) => controller.setAutoReRecordMaxRetries(v)
            : null,
      ),
    ),
  );
}),
```
