# 开播通知功能 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Simple Recorder 添加开播通知功能——只通知已 pin 的主播从"未开播→开播"的状态变化

**Architecture:** 在 `HomeController` 中新增 3 分钟定时器轮询 pin 主播直播状态，通过 `LiveNotificationService` 统一分发系统通知栏推送 + App 内 SnackBar 提示，`AppSettingsController` 提供总开关

**Tech Stack:** Flutter, GetX, flutter_local_notifications, flutter_background_service, simple_live_core

---

### Task 1: 添加依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 在 `pubspec.yaml` 中添加 `flutter_local_notifications` 依赖**

在 `pubspec.yaml` 的 dependencies 区域中，紧跟着 `flutter_background_service` 那行后面添加：

```yaml
  # 通知
  flutter_local_notifications: ^19.0.0
```

确定目标位置：搜索 `flutter_background_service` 行，在其后添加。

- [ ] **Step 2: 运行 `flutter pub get`**

```bash
flutter pub get
```
预期：依赖安装成功，无错误。

- [ ] **Step 3: 验证项目仍可分析**

```bash
flutter analyze
```
预期：无新增 error/warning（该命令可能产生一些 pre-existing hints，忽略即可）。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: add flutter_local_notifications dependency for live notification"
```

---

### Task 2: 新建 LiveNotificationService

**Files:**
- Create: `lib/services/live_notification_service.dart`

- [ ] **Step 1: 创建 `lib/services/live_notification_service.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';

class LiveNotificationService with WidgetsBindingObserver {
  static final LiveNotificationService _instance = LiveNotificationService._();
  static LiveNotificationService get instance => _instance;
  LiveNotificationService._();

  FlutterLocalNotificationsPlugin? _plugin;
  final Set<String> _notifiedLiveIds = {};
  bool _appInForeground = true;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);

    _plugin = FlutterLocalNotificationsPlugin();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin?.initialize(initSettings);

    // 注册 Android NotificationChannel
    const androidChannel = AndroidNotificationChannel(
      'live_notification',
      '开播提醒',
      description: 'Pin 的主播开播时发送通知',
      importance: Importance.high,
    );
    await _plugin
        ?.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    Log.logPrint("开播通知服务已初始化");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  /// 通知主播开播
  /// - 系统通知：始终发送
  /// - SnackBar：仅在前台时显示
  Future<void> notifyLiveStart(FollowUser user) async {
    if (_notifiedLiveIds.contains(user.id)) return;
    _notifiedLiveIds.add(user.id);

    // 系统通知栏
    try {
      await _plugin?.show(
        user.id.hashCode.abs(),
        '${user.userName} 开播了！',
        '点击查看直播间',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'live_notification',
            '开播提醒',
            channelDescription: 'Pin 的主播开播时发送通知',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      Log.logPrint("发送系统通知失败: $e");
    }

    // 前台 SnackBar
    if (_appInForeground) {
      Get.snackbar(
        '开播提醒',
        '${user.userName} 开播了！',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 4),
        backgroundColor: Get.theme?.colorScheme.primaryContainer,
        colorText: Get.theme?.colorScheme.onPrimaryContainer,
        margin: const EdgeInsets.all(12),
        borderRadius: 8,
      );
    }
  }

  /// 主播下播后清除去重记录，允许下次开播时重新通知
  void clearNotified(String id) {
    _notifiedLiveIds.remove(id);
  }

  /// 释放资源
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
```

- [ ] **Step 2: 验证文件无语法错误**

```bash
flutter analyze lib/services/live_notification_service.dart
```
预期：无 error/warning。

- [ ] **Step 3: Commit**

```bash
git add lib/services/live_notification_service.dart
git commit -m "feat: add LiveNotificationService for live notification dispatch"
```

---

### Task 3: main.dart 初始化通知服务

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 在 `main.dart` 中 import 并初始化**

在 `lib/main.dart` 顶部添加 import：
```dart
import 'package:simple_recorder/services/live_notification_service.dart';
```

在 `_requestPermissions()` 调用之后、`_markInterruptedFiles()` 之前或之后，添加初始化调用。找到 `_requestPermissions()` 调用行：

```dart
  // 新用户首启：请求通知权限和存储权限
  _requestPermissions();
```

在其后添加：
```dart
  // 初始化开播通知服务
  LiveNotificationService.instance.init();
```

- [ ] **Step 2: 在 `_requestPermissions()` 中加上通知权限请求**

当前 `_requestPermissions()`:
```dart
void _requestPermissions() {
  Future(() async {
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  });
}
```

改为：
```dart
void _requestPermissions() {
  Future(() async {
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    // 请求通知权限（Android 13+）
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  });
}
```

- [ ] **Step 3: 静态分析验证**

```bash
flutter analyze lib/main.dart
```
预期：无 error/warning。

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: initialize LiveNotificationService and request notification permission on startup"
```

---

### Task 4: AppSettingsController 添加开关

**Files:**
- Modify: `lib/app/controller/app_settings_controller.dart`
- Modify: `lib/app/constant.dart`

- [ ] **Step 1: 在 `Constant` 中添加事件 key**

在 `lib/app/constant.dart` 的 `Constant` 类中，紧跟 `kUpdateRecording` 后添加：

```dart
  static const String kUpdateRecording = "update_recording";
  static const String kPinnedFollowChanged = "pinned_follow_changed";
```

- [ ] **Step 2: 在 `AppSettingsController` 中添加开关**

在 `lib/app/controller/app_settings_controller.dart` 中做以下修改：

**添加 import：**
```dart
import 'package:simple_recorder/app/event_bus.dart';
```

**在 `autoSaveToFolder` 声明后添加新字段：**
```dart
  final autoSaveToFolder = true.obs;

  /// 开播通知开关（默认开启）
  final liveNotificationEnabled = true.obs;
```

**在 `loadSettings()` 方法末尾添加：**
```dart
    liveNotificationEnabled.value = LocalStorageService.instance
        .getValue("live_notification_enabled", true);
```

**在 `setAutoSaveToFolder()` 后添加 setter：**
```dart
  void setLiveNotificationEnabled(bool value) {
    liveNotificationEnabled.value = value;
    LocalStorageService.instance.setValue("live_notification_enabled", value);
    // 通知 HomeController 重新同步 poller 状态
    EventBus.instance.emit(Constant.kPinnedFollowChanged, null);
  }
```

**修改 `toggleFollowPin()` 末尾，emit 事件：**

在 `savePinnedFollowIds()` 调用之后、方法返回之前，添加：
```dart
    await savePinnedFollowIds();
    // 通知 HomeController pin 状态已变化
    EventBus.instance.emit(Constant.kPinnedFollowChanged, id);
```

**修改 `loadPinnedFollowIds()` 末尾，在 catch/finally 之后 emit 事件：**

在 `loadPinnedFollowIds()` 方法末尾添加：
```dart
    // 初始化加载完成后通知
    EventBus.instance.emit(Constant.kPinnedFollowChanged, null);
```

完整改后的 `toggleFollowPin`:
```dart
  Future<void> toggleFollowPin(String id) async {
    if (pinnedFollowIds.contains(id)) {
      pinnedFollowIds.remove(id);
    } else {
      pinnedFollowIds.add(id);
    }
    await savePinnedFollowIds();
    EventBus.instance.emit(Constant.kPinnedFollowChanged, id);
  }
```

- [ ] **Step 3: 验证**

```bash
flutter analyze lib/app/controller/app_settings_controller.dart lib/app/constant.dart
```
预期：无 error/warning。

- [ ] **Step 4: Commit**

```bash
git add lib/app/controller/app_settings_controller.dart lib/app/constant.dart
git commit -m "feat: add liveNotificationEnabled setting and pinned-follow-changed event"
```

---

### Task 5: HomeController 改造（核心轮询逻辑）

**Files:**
- Modify: `lib/modules/home/home_controller.dart`

- [ ] **Step 1: 添加 import**

在文件顶部，紧跟现有 import 后添加：

```dart
import 'dart:async';
import 'package:flutter/material.dart';  // 如果尚未导入（应该已导入）
import 'package:simple_recorder/services/live_notification_service.dart';
```

（注意：检查是否已有 `dart:async` 和 `package:flutter/material.dart` import，如有则跳过。）

- [ ] **Step 2: 修改 class 声明**

将 `class HomeController extends GetxController {` 改为：

```dart
class HomeController extends GetxController with WidgetsBindingObserver {
```

- [ ] **Step 3: 新增字段**

在现有字段声明区域（`isLoading` / `loadProgress` / `filterMode` 等之后），添加：

```dart
  /// 开播通知定时器
  Timer? _livePoller;

  /// 生命周期监听
  StreamSubscription<dynamic>? _pinSubscription;

  /// 首次检测标志：冷启动时不通知（只建立基线）
  bool _firstPinCheckDone = false;
```

- [ ] **Step 4: 在 `onInit()` 中添加 poller 启动和事件监听**

在 `onInit()` 末尾（`}` 闭合前）添加：

```dart
    // 启动开播通知轮询
    _syncPoller();
    // 监听 pin 状态变化
    _pinSubscription =
        EventBus.instance.listen(Constant.kPinnedFollowChanged, (_) {
      _syncPoller();
    });
    // 监听 App 生命周期
    WidgetsBinding.instance.addObserver(this);
```

注意：使用 `Constant.kPinnedFollowChanged` 需要确认 `lib/app/constant.dart` 已导入（现有 import 包含 `constant.dart`）。

- [ ] **Step 5: 在 `onClose()` 中添加清理**

在 `onClose()` 末尾（`}` 闭合前）添加：

```dart
    _livePoller?.cancel();
    _pinSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
```

- [ ] **Step 6: 新增 `_syncPoller()` 方法**

在 `loadFollowList()` 方法之前添加：

```dart
  /// 根据 pin 状态和总开关同步 poller 的启停
  void _syncPoller() {
    final settings = AppSettingsController.instance;
    final hasPinned = settings.pinnedFollowIds.isNotEmpty;
    final shouldRun = settings.liveNotificationEnabled.value && hasPinned;

    if (shouldRun && _livePoller == null) {
      _firstPinCheckDone = false; // 重新启用时重置基线标志
      _livePoller = Timer.periodic(
        const Duration(minutes: 3),
        (_) => _checkPinnedLiveStatus(notify: true),
      );
      // 立即执行首次检测（建立基线，不通知）
      _checkPinnedLiveStatus(notify: false);
    } else if (!shouldRun && _livePoller != null) {
      _livePoller?.cancel();
      _livePoller = null;
      _firstPinCheckDone = false;
    }
  }
```

- [ ] **Step 7: 新增 `_checkPinnedLiveStatus()` 方法**

在 `_sortByPin()` 方法之后添加：

```dart
  /// 检测已 pin 主播的直播状态
  /// notify=true 时发现开播会触发通知（自动轮询）
  /// notify=false 时只更新状态不通知（首次建立基线）
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
          // 开播（1→2），且不是首次建立基线
          await LiveNotificationService.instance.notifyLiveStart(user);
        }
        if (!isLive) {
          // 下播或变未知 → 清除去重标记
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
```

- [ ] **Step 8: 在现有 `checkAllLiveStatus()` 中复用 pin 检测**

在 `checkAllLiveStatus()` 方法中，`filterData()` 和 `isLoading.value = false;` 之前添加 pin 检测逻辑。找到方法末尾：

```dart
    filterData();
    isLoading.value = false;
```

在其前面添加一行调用：
```dart
    // 同时检测 pin 主播状态并触发通知（手动刷新时）
    _checkPinnedLiveStatus(notify: true);

    filterData();
    isLoading.value = false;
```

- [ ] **Step 9: 实现 `didChangeAppLifecycleState()`**

在 `_syncLists` 方法之后添加：

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPoller();
      // 切回前台时立即跑一次检测
      _checkPinnedLiveStatus(notify: true);
    } else if (state == AppLifecycleState.paused) {
      // 无录制时暂停 poller
      if (RecordingManager.instance.activeSessions.isEmpty) {
        _livePoller?.cancel();
        _livePoller = null;
      }
    }
  }
```

- [ ] **Step 10: 验证**

```bash
flutter analyze lib/modules/home/home_controller.dart
```
预期：无 error/warning。

- [ ] **Step 11: Commit**

```bash
git add lib/modules/home/home_controller.dart
git commit -m "feat: add live poller with pinned-user status detection and lifecycle-aware scheduling"
```

---

### Task 6: 设置页添加开关

**Files:**
- Modify: `lib/modules/settings/settings_page.dart`

- [ ] **Step 1: 在设置页的"录制" section 中添加开播通知开关**

在设置页的 `_sectionTitle("录制")` 和 `SettingsCard` 之间，找到现有录制开关区域。当前录制 section 中有 `autoSaveToFolder` 的 `SwitchListTile`。在其后添加开播通知开关。

在 `SwitchListTile` 的 `onChanged: (v) => controller.setAutoSaveToFolder(v),` 行和 `))` 闭包之间，添加：

```dart
                    )),
                    const Divider(height: 1, indent: 16),
                    Obx(() => SwitchListTile(
                          title: const Text("开播通知"),
                          subtitle: const Text("Pin 的主播开播时通知（每 3 分钟检测一次）"),
                          value: controller.liveNotificationEnabled.value,
                          onChanged: (v) =>
                              controller.setLiveNotificationEnabled(v),
                        )),
```

完整上下文（替换原有录制 section 的 SettingsCard 内部）：

```dart
          _sectionTitle("录制"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(() => SwitchListTile(
                      title: const Text("按主播名自动创建文件夹"),
                      subtitle: const Text("保存时自动存进主播名称的文件夹"),
                      value: controller.autoSaveToFolder.value,
                      onChanged: (v) => controller.setAutoSaveToFolder(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("开播通知"),
                      subtitle: const Text("Pin 的主播开播时通知（每 3 分钟检测一次）"),
                      value: controller.liveNotificationEnabled.value,
                      onChanged: (v) =>
                          controller.setLiveNotificationEnabled(v),
                    )),
              ],
            ),
          ),
```

- [ ] **Step 2: 验证**

```bash
flutter analyze lib/modules/settings/settings_page.dart
```
预期：无 error/warning。

- [ ] **Step 3: Commit**

```bash
git add lib/modules/settings/settings_page.dart
git commit -m "feat: add live notification toggle in settings page"
```

---

### Task 7: 全量静态分析验证

**Files:**
- 无新建/修改，只验证

- [ ] **Step 1: 全局静态分析**

```bash
flutter analyze
```
预期：无 error/warning。如有问题，修复后重新提交。

- [ ] **Step 2: 最终 commit（如有修复）**

如有修复：
```bash
git add .
git commit -m "chore: fix lint issues from live notification feature"
```

---

## Plan Self-Review

**1. Spec coverage:**

| Spec requirement | Covered by Task |
|---|---|
| R1: 仅通知已 pin 主播 | Task 5 (_checkPinnedLiveStatus checks pinnedFollowIds) |
| R2: 后台定时轮询 (3 分钟) | Task 5 (_syncPoller creates Timer.periodic) |
| R3: 前台/后台双通道通知 | Task 2 (notifyLiveStart with SnackBar + system notification) |
| R4: 单次通知 | Task 2 (_notifiedLiveIds set) |
| R5: 开播后刷新列表 | Task 5 (filterData() at end of _checkPinnedLiveStatus) |
| R6: 总开关 | Task 4 (liveNotificationEnabled field + EventBus) + Task 6 (UI) |
| R7: 手动刷新也触发通知 | Task 5 (checkAllLiveStatus calls _checkPinnedLiveStatus(notify:true)) |

**2. Placeholder scan:** 无 TBD/TODO/"implement later"。无"Add error handling"类空泛描述。所有步骤包含具体代码。

**3. Type consistency:** 
- `LiveNotificationService.notifyLiveStart(FollowUser)` — 参数类型一致
- `_checkPinnedLiveStatus({bool notify})` — 命名一致
- `Constant.kPinnedFollowChanged` — 定义于 Task 4，使用于 Task 5，一致
