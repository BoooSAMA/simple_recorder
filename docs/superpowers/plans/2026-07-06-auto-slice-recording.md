# 自动切片录制实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 录制过程中按用户设定的分钟间隔自动切分当前 TS 文件 → 重命名 → 自动解包为 M4A，然后无缝衔接继续录制

**Architecture:** AppSettingsController 新增两个 Rx 设置字段 → RecordingSession 在每秒定时器中检测切片条件 → 满足时取消当前 FFmpeg 进程走切片分支（重命名+解包+重启）→ SettingsPage 添加开关+间隔选择器

**Tech Stack:** Flutter, GetX, Hive, FFmpegKit

---

### Task 1: AppSettingsController — 新增设置字段

**Files:**
- Modify: `lib/app/controller/app_settings_controller.dart`

- [ ] **Step 1: 新增 autoSliceEnabled / autoSliceIntervalMinutes 字段**

在 `AppSettingsController` 类中，`deleteTsAfterUnpack` 字段之后添加：

```dart
  /// 自动切片录制
  final autoSliceEnabled = false.obs;
  final autoSliceIntervalMinutes = 30.obs;
```

- [ ] **Step 2: 在 loadSettings() 中加载**

在 `loadSettings()` 方法中，`deleteTsAfterUnpack` 加载之后添加：

```dart
    autoSliceEnabled.value = LocalStorageService.instance
        .getValue("auto_slice_enabled", false);
    autoSliceIntervalMinutes.value = LocalStorageService.instance
        .getValue("auto_slice_interval", 30);
```

- [ ] **Step 3: 添加 setter 方法**

在 `setDeleteTsAfterUnpack` 方法之后添加：

```dart
  void setAutoSliceEnabled(bool value) {
    autoSliceEnabled.value = value;
    LocalStorageService.instance.setValue("auto_slice_enabled", value);
  }

  void setAutoSliceIntervalMinutes(int minutes) {
    final clamped = minutes.clamp(1, 240);
    autoSliceIntervalMinutes.value = clamped;
    LocalStorageService.instance.setValue("auto_slice_interval", clamped);
  }
```

- [ ] **Step 4: 验证无分析错误**

Run: `flutter analyze lib/app/controller/app_settings_controller.dart`
Expected: 0 errors, 0 warnings

- [ ] **Step 5: Commit**

```bash
git add lib/app/controller/app_settings_controller.dart
git commit -m "feat: add auto-slice settings to AppSettingsController"
```

---

### Task 2: RecordingSession — 核心切片逻辑

**Files:**
- Modify: `lib/services/recording_service.dart`

- [ ] **Step 1: 新增字段和 _stopRequested 保护**

在 `RecordingSession` 类的 `_isInterrupted` 字段之后（第390行附近），新增：

```dart
  bool _isSlicing = false;
  int _sliceIntervalSeconds = 0;
  bool _stopRequested = false;
```

- [ ] **Step 2: 在 start() 中读取切片配置**

在 `start()` 方法中，`_retries = 0;`（第216行）之后添加：

```dart
    // 读取切片设置
    var sliceEnabled = AppSettingsController.instance.autoSliceEnabled.value;
    var sliceMinutes = AppSettingsController.instance.autoSliceIntervalMinutes.value;
    _sliceIntervalSeconds = (sliceEnabled && sliceMinutes > 0) ? sliceMinutes * 60 : 0;
    _stopRequested = false;
```

- [ ] **Step 3: 在 _timer 回调中添加切片检测**

在 `_timer` 的每秒回调中，在 `sizeTickCounter++`（第246行）之前、停滞检测（第235-244行）之后，插入切片检测：

```dart
        // 切片检测：达到设定秒数时自动切分
        if (!_isSlicing && _sliceIntervalSeconds > 0 && _seconds > 0 &&
            _seconds % _sliceIntervalSeconds == 0) {
          _isSlicing = true;
          Log.logPrint("自动切片触发: $_outputPath, 已录制 ${_seconds}s");
          _doCancelFFmpeg();
          return;
        }
```

完整的 timer callback 修改后的样子：

```dart
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      var m = (_seconds ~/ 60).toString().padLeft(2, '0');
      var s = (_seconds % 60).toString().padLeft(2, '0');
      duration.value = "$m:$s";
      // 文件大小每 5 秒轮询一次，减少系统调用
      if (sizeTickCounter % 5 == 0) {
        fileSize.value = _formatFileSize(_outputPath);
        // 停滞检测：服务器限流导致 FFmpeg 无限重连，文件始终 0B
        if (_seconds > 90 && fileSize.value == "0 B") {
          lastError.value = "录制停滞，可能服务器限流，已自动结束";
          Log.logPrint("检测到录制停滞，自动结束: $_outputPath, ${_seconds}s");
          _onFinished();
          return;
        }
        if (_seconds > 60 && fileSize.value == "0 B") {
          lastError.value = "录制异常：长时间无数据写入（可能服务器限流）";
          Log.logPrint("录制停滞预警: $_outputPath, ${_seconds}s");
        }
      }
      // 切片检测：达到设定秒数时自动切分
      if (!_isSlicing && _sliceIntervalSeconds > 0 && _seconds > 0 &&
          _seconds % _sliceIntervalSeconds == 0) {
        _isSlicing = true;
        Log.logPrint("自动切片触发: $_outputPath, 已录制 ${_seconds}s");
        _doCancelFFmpeg();
        return;
      }
      sizeTickCounter++;
    });
```

- [ ] **Step 4: 修改 stop() 设置 _stopRequested**

在 `stop()` 方法开头添加：

```dart
  Future<void> stop() async {
    _stopRequested = true;
    _discardRequested = false;
    ...
```

- [ ] **Step 5: 修改 cancel() 设置 _stopRequested**

在 `cancel()` 方法开头添加：

```dart
  Future<void> cancel() async {
    _stopRequested = true;
    _discardRequested = true;
    ...
```

- [ ] **Step 6: 在 _onFinished() 中新增切片分支**

修改 `_onFinished()` 方法，在文件处理（重命名+解包）之后、资源释放之前，插入切片分支判断：

```dart
  Future<void> _onFinished() async {
    if (_finished) return;
    _finished = true;
    if (_startTime != null && _outputPath.isNotEmpty && !_discardRequested) {
      await _renameFileWithEndTime();
      // 成功完成录音后，自动解包 TS → 目标格式
      if (_outputPath.endsWith('.ts')) {
        await _autoUnpackToTargetFormat();
      }
    }
    // === 切片分支：切片时重置状态并重新开始，不释放资源也不通知 manager ===
    if (_isSlicing && !_stopRequested) {
      _isSlicing = false;
      _finished = false;
      _startTime = null;
      _sessionId = null;
      _timer?.cancel();
      _timer = null;
      isRecording.value = false;
      // 释放引用计数（让 start() 重新获取）
      _releaseWakelock();
      _releaseForegroundService();
      // 刷新播放地址
      await _onRefreshPlayUrl?.call();
      Log.logPrint("切片完成，开始下一段录制");
      start();
      return;
    }
    // === 正常结束流程 ===
    _startTime = null;
    _timer?.cancel();
    _timer = null;
    isRecording.value = false;
    _sessionId = null;
    // 录制结束时释放唤醒锁和前台服务
    _releaseWakelock();
    _releaseForegroundService();
    _finishCompleter?.complete();
    // 通知 RecordingManager 从 activeSessions 中移除
    onFinished?.call();
  }
```

- [ ] **Step 7: 验证无分析错误**

Run: `flutter analyze lib/services/recording_service.dart`
Expected: 0 errors, 0 warnings

- [ ] **Step 8: Commit**

```bash
git add lib/services/recording_service.dart
git commit -m "feat: implement auto-slice logic in RecordingSession"
```

---

### Task 3: SettingsPage — 添加自动切片 UI

**Files:**
- Modify: `lib/modules/settings/settings_page.dart`

- [ ] **Step 1: 在"录制"设置分类中添加自动切片 UI**

在 `SettingsPage` 的录制分类（`_sectionTitle("录制")` 下的 `SettingsCard`），在 `deleteTsAfterUnpack` 的 Divider 之后、card 的 Column 结束之前，添加自动切片开关和间隔选择器：

```dart
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("自动切片录制"),
                      subtitle: const Text("按设定间隔自动切分并解包 TS 文件"),
                      value: controller.autoSliceEnabled.value,
                      onChanged: (v) =>
                          controller.setAutoSliceEnabled(v),
                    )),
                Obx(() {
                  var enabled = controller.autoSliceEnabled.value;
                  var interval = controller.autoSliceIntervalMinutes.value;
                  return Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "切片间隔",
                        value: interval,
                        min: 1,
                        max: 240,
                        step: 10,
                        unit: " 分钟",
                        displayValue: "$interval 分钟",
                        subtitle: "范围 1~240 分钟",
                        onChanged: enabled
                            ? (v) =>
                                controller.setAutoSliceIntervalMinutes(v)
                            : null,
                      ),
                    ),
                  );
                }),
```

- [ ] **Step 2: 验证无分析错误**

Run: `flutter analyze lib/modules/settings/settings_page.dart`
Expected: 0 errors, 0 warnings

- [ ] **Step 3: 全量分析验证**

Run: `flutter analyze`
Expected: 0 errors, 0 warnings (pre-existing infos may remain)

- [ ] **Step 4: Commit**

```bash
git add lib/modules/settings/settings_page.dart
git commit -m "feat: add auto-slice settings UI"
```

---

### Task 4: 集成验证

- [ ] **Step 1: 确认所有代码一致**

确认三个文件的改动在类型和方法签名上一致：
- `AppSettingsController` 暴露了 `autoSliceEnabled`, `autoSliceIntervalMinutes` 及其 setter
- `RecordingSession` 引用的 `AppSettingsController.instance.autoSliceEnabled.value` 和 `.autoSliceIntervalMinutes.value` 存在
- `SettingsPage` 引用的 `controller.autoSliceEnabled.value`, `.setAutoSliceEnabled(v)`, `.autoSliceIntervalMinutes.value`, `.setAutoSliceIntervalMinutes(v)` 存在

- [ ] **Step 2: 运行最终分析**

Run: `flutter analyze`
Expected: 0 errors, 0 warnings

- [ ] **Step 3: 最终提交**

```bash
git commit --allow-empty -m "feat: complete auto-slice recording feature"
```
