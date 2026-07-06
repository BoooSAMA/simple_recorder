# 自动切片录制设计文档

**日期**: 2026-07-06
**状态**: 草案

## 概述

为防止长时间录制过程中因意外中断（网络闪断、进程崩溃等）导致整个 TS 文件损坏或丢失，增加**自动切片录制**功能。录制过程中按用户设定的时间间隔自动切分当前 TS 文件 → 重命名 → 自动解包为 M4A，然后无缝衔接开始下一段录制。

## 设置项

在 `AppSettingsController` 新增两个字段，存储于 Hive：

| 字段 | 类型 | 默认值 | Hive key | 说明 |
|------|------|--------|----------|------|
| `autoSliceEnabled` | `RxBool` | `false` | `auto_slice_enabled` | 是否启用自动切片 |
| `autoSliceIntervalMinutes` | `RxInt` | `30` | `auto_slice_interval` | 切片间隔（分钟） |

约束：
- 范围：1 ~ 240 分钟
- 默认值：30 分钟
- 步进按钮每次 ±10 分钟（超出范围自动 clamp）
- 底部滑块可精确拖动选择任意值

## 设置页 UI

位于 **设置 → 录制** 分类下：

```
┌──────────────────────────────────────────┐
│ 自动切片录制                         [开关] │
│ 按设定间隔自动切分并解包 TS 文件          │
├──────────────────────────────────────────┤
│ 切片间隔         [-]  30 分钟  [+]        │
│ 范围 1~240 分钟    (滑动条/自定义)        │
└──────────────────────────────────────────┘
```

- 开关关闭时，间隔选择器整体置灰/禁用
- 开关开启时，间隔选择器可操作
- 步进按钮单击 ±10，长按可快速调节
- 点击数字区域弹出底部 Sheet：Slider + 确定按钮

## 录制层切片逻辑

### 核心流程

在 `RecordingSession` 中新增切片机制，流程图如下：

```
_timer 每秒回调
  ↓
_seconds > 0 && _seconds % sliceInterval == 0 && !_isSlicing
  ↓
设置 _isSlicing = true
  ↓
取消当前 _timer
  ↓
_doCancelFFmpeg()                       ← 正常结束当前 FFmpeg 进程
  ↓
FFmpeg cancel 回调触发
  ↓
_onFinished()
  ├── _isSlicing == true ────────────────────┐
  │                                          │
  │  _renameFileWithEndTime()                │
  │  _autoUnpackToTargetFormat()             │
  │  _finished = false (允许下次切片)          │
  │  isRecording.value = false               │
  │  _releaseWakelock()                      │
  │  _releaseForegroundService()             │
  │  await _onRefreshPlayUrl?.call()         │
  │  start()                    ← 重新开始录制  │
  │                                          │
  │  return (不调 onFinished)                 │
  └──────────────────────────────────────────┘
  │
  └── _isSlicing == false ─── 正常结束流程
                              _releaseWakelock()
                              _releaseForegroundService()
                              onFinished?.call() ← 通知 manager 移除 session
```

### 关键设计决策

1. **引用计数平衡**：切片时先释放唤醒锁/前台服务（计数退一），`start()` 重新获取（计数加一），确保引用计数始终正确。

2. **不脱离 activeSessions**：切片时不调用 `onFinished?.call()`，因此 `RecordingManager` 不会移除此 session。对 UI 而言，录制从未中断。

3. **时长计数器重置**：切片后 `_seconds` 归零，UI 上的"已录制 00:05:30"显示当前片段的时长，而非总时长。

4. **播放地址刷新**：切片后调用 `_onRefreshPlayUrl?.call()` 获取最新播放地址，避免旧 URL 过期导致录制中断。

5. **防重入**：`_isSlicing` 标志防止在切片进行中再次触发切片（FFmpeg cancel + restart 期间）。

6. **`_stopRequested` 保护**：若用户在切片过程中调用 `stop()`/`cancel()`，`_onFinished()` 切片路径检测到 `_stopRequested` 标志后放弃重启，走正常结束流程，确保用户停止意图不被切片逻辑覆盖。

7. **解包行为**：沿用现有 `_autoUnpackToTargetFormat()`，根据用户设置的音频格式进行 remux，解包选项（如"解包后删除 TS 文件"）同样生效。

### 代码变更

**`RecordingSession` 新增字段：**
- `bool _isSlicing = false` — 切片中标志
- `int _sliceIntervalSeconds = 0` — 从分钟转换的秒数，在 `start()` 中初始化

**`RecordingSession._timer` 回调中新增切片检测：**
- 在停滞检测之后、`sizeTickCounter` 更新之前，检查切片条件
- 条件：`_isSlicing == false && _sliceIntervalSeconds > 0 && _seconds > 0 && _seconds % _sliceIntervalSeconds == 0`

**`RecordingSession._onFinished()` 中新增切片分支：**
- 在文件处理（重命名+解包）之后，检测 `_isSlicing`
- 切片分支：重置状态 → 释放资源 → 刷新 URL → 调用 `start()`
- 正常分支：保持不变

## 文件清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `lib/app/controller/app_settings_controller.dart` | 修改 | 新增 autoSliceEnabled / autoSliceIntervalMinutes 字段及 setter |
| `lib/services/recording_service.dart` | 修改 | 实现切片核心逻辑 |
| `lib/modules/settings/settings_page.dart` | 修改 | 新增自动切片设置 UI |
| `docs/superpowers/specs/2026-07-06-auto-slice-recording-design.md` | 新增 | 本文档 |

## 边界情况

| 场景 | 行为 |
|------|------|
| 切片触发但 FFmpeg 已出错退出（重试中） | `isRecording.value` 为 true 但 `_sessionId` 为 null，`_doCancelFFmpeg` 走 `!hadActiveSession` 分支直接调 `_onFinished`，切片依然能正确走通 |
| 用户手动停止录制恰好在切片时 | `_stopRequested` 标志确保切片路径放弃重启，走正常结束流程，`onFinished?.call()` 正常触发移除 session |
| 切片间隔设为 1 分钟 | 每分钟切片一次，适用于极端场景，但会增加解包开销 |
| 切片间隔设为 240 分钟 | 4 小时切一次，兼顾防丢失与性能 |
| 录制时长不足一个切片间隔 | 不会触发切片，录制结束后正常完成 + 解包 |
| 录制过程中更改切片设置 | 当前录制 session 使用 start() 时读取的旧值，下次切片后重新 start() 时读取新值 |
