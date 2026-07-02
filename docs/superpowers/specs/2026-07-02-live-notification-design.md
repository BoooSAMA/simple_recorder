# 开播通知功能 — 设计文档

**Date:** 2026-07-02
**Branch:** main
**Version:** Simple Recorder 1.3.1+1

## Overview

为 Simple Recorder 添加开播通知功能。只通知已 pin 的主播从"未开播→开播"时的状态变化，不通知未 pin 的关注主播。

## Requirements

| # | 需求 | 详情 |
|---|------|------|
| R1 | 仅通知已 pin 主播 | 通过 `AppSettingsController.pinnedFollowIds` 过滤 |
| R2 | 后台定时轮询 | 每 3 分钟检测一次 pin 主播的直播状态 |
| R3 | 前台/后台双通道通知 | 前台用 SnackBar，后台/锁屏用系统通知栏 |
| R4 | 单次通知 | 每个主播每次开播周期只通知一次 |
| R5 | 开播后刷新列表 | 检测到开播后自动更新首页直播间列表 |
| R6 | 总开关 | 设置页提供开播通知总开关，默认开启 |
| R7 | 不重复通知已有逻辑 | 手动刷新和自动轮询共享去重机制 |

## Design Decision

**方案 A：主 Isolate 定时轮询 + 录制保活**

轮询逻辑在 `HomeController` 主 isolate 中运行（`Timer.periodic`），利用现有录制前台服务（`flutter_background_service`）间接保活：
- 有录制时 → 后台服务活跃 → Timer 在后台继续运行
- 无录制且切后台 → Timer 暂停（系统允许的合理行为）

## Architecture

```
main.dart
 └─ LiveNotificationService.init()  ← 新增初始化

HomeController (改造)
 ├─ _livePoller: Timer?              ← 新增: 3 分钟定时器
 ├─ _notifiedLiveIds: Set<String>    ← 移至 LiveNotificationService
 ├─ _appInForeground: bool           ← 新增: 前后台状态
 ├─ _syncPoller()                    ← 新增: 根据 pin 状态启/停 poller
 ├─ _checkPinnedLiveStatus()         ← 新增: pin-only 状态检测
 └─ AppLifecycleState 监听           ← 新增

AppSettingsController (改造)
 └─ liveNotificationEnabled: RxBool  ← 新增: 总开关

LiveNotificationService (新文件)
 ├─ FlutterLocalNotificationsPlugin  ← 系统通知能力
 ├─ _notifiedLiveIds: Set<String>    ← 防重复去重
 ├─ notifyLiveStart(FollowUser)      ← 智能分发(系统通知+SnackBar)
 └─ clearNotified(String id)         ← 下播后清除去重记录

SettingsPage (改造)
 └─ "开播通知" Switch 行              ← 新增 UI
```

## New Files

| 文件 | 用途 |
|------|------|
| `lib/services/live_notification_service.dart` | 通知分发（系统通知 + SnackBar）+ 去重管理 |

## New Dependencies

| 依赖 | 版本 | 用途 |
|------|------|------|
| `flutter_local_notifications` | ^19.0.0 | Android/iOS 系统通知栏推送 |

## Modified Files

| 文件 | 改动 |
|------|------|
| `main.dart` | 启动时初始化 `LiveNotificationService` |
| `pubspec.yaml` | 添加 `flutter_local_notifications` 依赖 |
| `app/controller/app_settings_controller.dart` | 新增 `liveNotificationEnabled` 开关 + 持久化 |
| `modules/home/home_controller.dart` | 新增 poller + pin-only 检测 + 生命周期监听 |
| `modules/settings/settings_page.dart` | 新增"开播通知"开关行 |

## Component Detail

### LiveNotificationService

```dart
class LiveNotificationService {
  static final _instance = LiveNotificationService._();
  static LiveNotificationService get instance => _instance;

  FlutterLocalNotificationsPlugin _plugin;
  final Set<String> _notifiedLiveIds = {};

  /// 初始化：注册 Android channel，请求权限
  Future<void> init();

  /// 智能分发通知
  /// - 去重检查：已通知过的主播跳过
  /// - 始终发送系统通知（前后台均发）
  /// - 前台额外显示 SnackBar
  Future<void> notifyLiveStart(FollowUser user);

  /// 主播从开播变为未开播时清除去重记录
  void clearNotified(String id);
}
```

**Android NotificationChannel 配置**:
- ID: `"live_notification"`
- 名称: `"开播提醒"`
- 重要性: `Importance.high`（弹出 + 声音）

### HomeController 改造

新增字段和方法：

```
onInit()
  → _syncPoller()                           # 初始启动
  → 监听 AppLifecycleState                   # 前台/后台切换

onClose()
  → _livePoller?.cancel()                    # 清理定时器
  → _lifecycleSubscription?.cancel()

_syncPoller()
  → 检查 liveNotificationEnabled && pinnedFollowIds.isNotEmpty
  → 启动 Timer.periodic(3min) → _checkPinnedLiveStatus(notify: true)
  → pinnedFollowIds 为空时停止 poller

_checkPinnedLiveStatus({bool notify = false})
  → 遍历 followList 中 pinnedFollowIds 包含的用户
  → 调用 site.liveSite.getLiveStatus()
  → 检测到 1→2（开播）&& notify → LiveNotificationService.notifyLiveStart()
  → 检测到 2→1/0 → LiveNotificationService.clearNotified()
  → 完成后调用 filterData() 刷新 UI

生命周期监听
  → resumed → _syncPoller() + 立即执行一次检测
  → paused  → 无录制时 _livePoller?.cancel()；有录制时保持运行
```

### 去重生命周期

```
A 开播 ──→ _notifiedLiveIds.add(A.id)
    │
    ├─ 3 分钟后轮询 → 跳过 A（已在去重集合）
    ├─ A 下播 → _notifiedLiveIds.remove(A.id)
    │    └─ 下次开播可再次通知
    │
    └─ App 重启 → 集合清空 → 重新检测并通知
```

### Poller 启停触发点

| 触发事件 | 行为 |
|----------|------|
| 用户 pin 一个主播（且 pinnedFollowIds 从空变非空） | `_syncPoller()` → 启动 poller |
| 用户取消最后一个 pin | `_syncPoller()` → 停止 poller |
| 删除关注（包含 pin 的） | `_syncPoller()` → 如 pinnedFollowIds 变空则停止 |
| 导入关注数据 | `_syncPoller()` → 根据 pinnedFollowIds 状态调整 |
| 总开关打开→关闭 | `_syncPoller()` → 停止 poller |
| 总开关关闭→打开 | `_syncPoller()` → 恢复 poller |

## Edge Cases

| 场景 | 处理 |
|------|------|
| 网络请求失败（单个主播） | 捕获异常，设置状态为 0，不中断检测循环 |
| 手动刷新 + 自动轮询同时触发 | 共享去重集合，先到先记录 |
| pin 主播数为 0 | poller 不启动 |
| 总开关关闭 | poller 停止 |
| App 被系统杀进程 | 轮询停止（无录制时）；有录制时前台服务恢复 |
| 冷启动首次检测 | 先获取当前状态作为基线，不通知已有开播 |

## Known Limitations

- App 被系统杀进程（非录制期间）后轮询停止。录制前台服务运行时则持续。
- iOS 后台限制更严格，通知可靠性依赖系统策略。
- `flutter_background_service` 不是真·系统 service，无法在进程被 kill 后自动恢复。

## Acceptance Criteria

1. pin 一个主播后，该主播开播时在通知栏和 App 内都能收到通知
2. 同一轮开播周期内不重复通知
3. 手动刷新按钮也能触发开播通知
4. 设置页"开播通知"开关可以全局关闭
5. 录制期间切后台，开播通知仍能正常触发
6. 取消全部 pin 后 poller 停止
