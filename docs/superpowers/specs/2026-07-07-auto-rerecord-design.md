# 直播恢复自动续录 — 设计文档

**Date:** 2026-07-07
**Status:** Draft

## Summary

当录制因直播结束而自动停止时，启动一个分钟级的定时检测机制，在主播重新开播后自动恢复录制，避免因临时断流或直播中断导致录制不完整。

## Problem

现有机制处理毫秒级（FFmpeg reconnect）和秒级（`_scheduleRetry` 2s/4s/6s × 3次）中断，但无法应对"主播断流/直播间临时关闭后数分钟才重新开播"的场景。当前行为是：秒级重试耗尽 → 录制停止 → 不再尝试，导致主播重新开播后录制无法自动恢复。

## Glossary

| 术语 | 含义 |
|------|------|
| 秒级重试 | RecordingSession._scheduleRetry，2s/4s/6s 退避重试 FFmpeg 进程 |
| 分钟级续录 | 本设计新增功能，以分钟为间隔检测主播是否重新开播 |
| 续录队列 | 等待恢复录制的主播任务列表 |
| 自然结束 | 非用户主动停止，而是直播结束/重试耗尽导致的 session 终止 |

## Design

### 1. RecordingSession 改造

**改动：`lib/services/recording_service.dart`**

暴露 `_stopRequested` 字段用于区分"用户停止"和"自然结束"：

```dart
// 新增
bool get isUserStopped => _stopRequested;
```

`_onFinished()` 保持现有逻辑不变，但外部（RecordingManager）通过 `isUserStopped` 判断是否加入续录队列。

### 2. 设置项（AppSettingsController）

**改动：`lib/app/controller/app_settings_controller.dart`**

新增 3 个设置项：

| 字段 | 类型 | 默认值 | Hive key | 说明 |
|------|------|--------|----------|------|
| `autoReRecordEnabled` | `RxBool` | `false` | `autoReRecordEnabled` | 主开关 |
| `autoReRecordDelayMinutes` | `RxInt` | `5` | `autoReRecordDelayMinutes` | 检测间隔（1~30 分钟） |
| `autoReRecordMaxRetries` | `RxInt` | `3` | `autoReRecordMaxRetries` | 最大检测次数（1~10） |

配套 setter 方法：

```dart
void setAutoReRecordEnabled(bool v) { ... }
void setAutoReRecordDelayMinutes(int v) { ... }
void setAutoReRecordMaxRetries(int v) { ... }
```

### 3. RecordingManager → HomeController 通信

**改动：`lib/services/recording_manager.dart`**

增加跨模块事件流，让 HomeController 能监听到 session 自然结束：

```dart
// 新增 broadcast stream
final onSessionEnded = StreamController<RecordingSession>.broadcast();
```

在现有的 `onFinished` 回调末尾添加事件通知：

```dart
session.onFinished = () {
  activeSessions.remove(session);
  activeCount.value = activeSessions.length;
  onSessionEnded.add(session);  // 新增：通知外部
};
```

同时暴露 `isRecording()` 和 `startRecording()` 供续录逻辑复用。

### 4. 续录队列管理器（HomeController）

**改动：`lib/modules/home/home_controller.dart`**

新增内部数据结构 `_ReRecordTask`：

```dart
class _ReRecordTask {
  final String taskId;
  final String roomId;
  final String siteId;
  final String userName;
  int retriesLeft;
  int delayMinutes;
  Timer? timer;
}
```

新增字段和方法：

| 成员 | 类型 | 说明 |
|------|------|------|
| `_reRecordQueue` | `List<_ReRecordTask>` | 待续录任务列表 |
| `_addToReRecordQueue(session)` | 方法 | session 自然结束时调用，检查设置后加入队列 |
| `_processReRecordTask(task)` | 方法 | 检测主播状态，决定是否重新录制 |
| `_removeFromReRecordQueue(roomId)` | 方法 | 续录成功或达到最大次数时移除 |
| `_cancelAllReRecord()` | 方法 | 清理所有待续录任务 |

**核心流程：**

```
录制 session 自然结束 → _onFinished() → onFinished?.call()
  → RecordingManager: 从 activeSessions 移除 + onSessionEnded.add(session)
  → HomeController 监听 onSessionEnded
  → 判断：autoReRecordEnabled && !session.isUserStopped?
  → 是 → _addToReRecordQueue()
      → 创建 _ReRecordTask
      → 设置定时器：delayMinutes 分钟后触发（每个任务独立定时器）
  → 定时器到期 → _processReRecordTask()
      → _checkLiveStatus(roomId, siteId) 检测直播状态
      → 开播了 → 从续录队列移除
          → 检查对应 FollowUser 仍在关注列表
          → 创建新 RecordingSession → RecordingManager.startRecording()
      → 没开播 → retriesLeft-- → 还有次数 → 设下一个定时器
                  → 次数耗尽 → 从队列移除，记录日志

用户手动 stopRecording → isUserStopped=true → 不加入续录队列
```

### 4. 检测主播状态

复用 HomeController 现有的 `_checkLiveStatus` 方法。该方法接收 `(roomId, siteId)` 返回 `bool`，与当前流程一致。

### 5. 设置页面 UI

**改动：`lib/modules/settings/settings_page.dart`**

在"录制"分类下新增配置区域：

```
┌─ 录制 ──────────────────────────┐
│  按主播名自动创建文件夹          │
│  ─────────────────────────────── │
│  开播通知                        │
│  ─────────────────────────────── │
│  音频输出格式                    │
│  ─────────────────────────────── │
│  解包后删除 TS 文件              │
│  ─────────────────────────────── │
│  自动切片录制                    │
│  ─────────────────────────────── │
│  🔹 直播恢复自动续录  [开关]     │  ← 新增
│  🔹 检测间隔         5  分钟    │  ← 新增（受开关控制灰显）
│  🔹 最大检测次数     3  次      │  ← 新增（受开关控制灰显）
└─────────────────────────────────┘
```

使用现有 `SwitchListTile` + `SettingsNumber` 组件，与"自动切片"的灰显逻辑一致。

### 6. 生命周期管理

| 事件 | 行为 |
|------|------|
| App 进入后台 | 续录定时器不受影响（由 Dart 事件循环管理） |
| App 被杀死 | 续录队列丢失（后续可通过启动时扫描 + 用户手动续录？暂不实现） |
| 用户主动停止录制 | 从续录队列移除该 session |
| 用户删除关注 | 从续录队列移除 |
| App 退出 | `onClose()` 中清理所有续录定时器 |

### 7. 边界情况

| 场景 | 处理 |
|------|------|
| 主播在检测间隔内重新开播 | 等定时器到期才检测到→重新开始录制（最多延迟 xx 分钟） |
| 主播开播又结束在检测间隔内 | 检测到时已再次结束→继续等下一轮 |
| 用户手动停止录制 | `isUserStopped=true`，不加入续录队列 |
| 多个主播同时断流 | 每个 session 各自独立加入续录队列，独立定时器 |
| 用户关闭自动续录开关 | 清空续录队列，取消所有定时器 |

### Files Changed

| File | Change |
|------|--------|
| `lib/services/recording_service.dart` | 新增 `isUserStopped` getter |
| `lib/app/controller/app_settings_controller.dart` | 新增 3 个设置项 + setter |
| `lib/modules/home/home_controller.dart` | 续录队列 + 定时器 + 检测逻辑 |
| `lib/modules/settings/settings_page.dart` | 续录配置 UI |
