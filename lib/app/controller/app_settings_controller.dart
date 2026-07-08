import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/services/local_storage_service.dart';

class AppSettingsController extends GetxController {
  static AppSettingsController get instance => Get.find<AppSettingsController>();

  final themeMode = 0.obs;
  final isDynamic = true.obs;
  final styleColor = 0xFF1677FF.obs;
  final audioSavePath = "".obs;
  final logEnable = false.obs;
  final maxConcurrentRecordings = 3.obs;
  final autoReconnect = true.obs;
  final autoSaveToFolder = true.obs;
  final liveNotificationEnabled = true.obs;
  final livePollInterval = 5.obs;
  final autoRecordPinned = false.obs;

  /// 音频输出格式（m4a, mp3, flac, wav, ogg）
  final audioFormat = Constant.kAudioFormatM4A.obs;

  /// 自动解包后是否删除源 TS 文件
  final deleteTsAfterUnpack = true.obs;

  /// 自动切片录制
  final autoSliceEnabled = false.obs;
  final autoSliceIntervalMinutes = 30.obs;

  /// 直播恢复自动续录
  final autoReRecordEnabled = false.obs;
  final autoReRecordDelayMinutes = 5.obs;
  final autoReRecordMaxRetries = 3.obs;

  /// 直播状态检测并发数（5~50）
  final liveCheckConcurrency = 5.obs;

  /// 置顶的直播间 ID 集合
  var pinnedFollowIds = <String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
    loadPinnedFollowIds();
  }

  void loadSettings() {
    themeMode.value = LocalStorageService.instance
        .getValue("theme_mode", 0);
    isDynamic.value = LocalStorageService.instance
        .getValue("is_dynamic", true);
    styleColor.value = LocalStorageService.instance
        .getValue("style_color", 0xFF1677FF);
    audioSavePath.value = LocalStorageService.instance
        .getValue("audio_save_path", "");
    logEnable.value = LocalStorageService.instance
        .getValue("log_enable", false);
    maxConcurrentRecordings.value = LocalStorageService.instance
        .getValue("max_concurrent_recordings", 3);
    autoReconnect.value = LocalStorageService.instance
        .getValue("auto_reconnect", true);
    autoSaveToFolder.value = LocalStorageService.instance
        .getValue("auto_save_to_folder", true);
    liveNotificationEnabled.value = LocalStorageService.instance
        .getValue("live_notification_enabled", true);
    livePollInterval.value = LocalStorageService.instance
        .getValue("live_poll_interval", 5);
    autoRecordPinned.value = LocalStorageService.instance
        .getValue("auto_record_pinned", false);
    audioFormat.value = LocalStorageService.instance
        .getValue("audio_format", Constant.kAudioFormatM4A);
    deleteTsAfterUnpack.value = LocalStorageService.instance
        .getValue("delete_ts_after_unpack", true);
    autoSliceEnabled.value = LocalStorageService.instance
        .getValue("auto_slice_enabled", false);
    autoSliceIntervalMinutes.value = LocalStorageService.instance
        .getValue("auto_slice_interval", 30);
    autoReRecordEnabled.value = LocalStorageService.instance
        .getValue("auto_rerecord_enabled", false);
    autoReRecordDelayMinutes.value = LocalStorageService.instance
        .getValue("auto_rerecord_delay", 5);
    autoReRecordMaxRetries.value = LocalStorageService.instance
        .getValue("auto_rerecord_max_retries", 3);
    liveCheckConcurrency.value = LocalStorageService.instance
        .getValue("live_check_concurrency", 5);
  }

  /// 加载置顶直播间 ID 列表
  void loadPinnedFollowIds() {
    final raw = LocalStorageService.instance
        .getValue("pinned_follow_ids", "");
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        // ignore: invalid_use_of_protected_member
        pinnedFollowIds.value = decoded.cast<String>().toSet();
      } catch (_) {
        // ignore: invalid_use_of_protected_member
        pinnedFollowIds.value = {};
      }
    }
    EventBus.instance.emit(Constant.kPinnedFollowChanged, null);
  }

  /// 保存置顶直播间 ID 列表
  Future<void> savePinnedFollowIds() async {
    final encoded = jsonEncode(pinnedFollowIds.toList());
    await LocalStorageService.instance
        .setValue("pinned_follow_ids", encoded);
  }

  /// 判断直播间是否被置顶
  bool isFollowPinned(String id) => pinnedFollowIds.contains(id);

  /// 切换置顶状态
  Future<void> toggleFollowPin(String id) async {
    if (pinnedFollowIds.contains(id)) {
      pinnedFollowIds.remove(id);
    } else {
      pinnedFollowIds.add(id);
    }
    await savePinnedFollowIds();
    EventBus.instance.emit(Constant.kPinnedFollowChanged, id);
  }

  void setThemeMode(int mode) {
    themeMode.value = mode;
    Get.changeThemeMode(ThemeMode.values[mode]);
    LocalStorageService.instance.setValue("theme_mode", mode);
  }

  void setAudioSavePath(String path) {
    audioSavePath.value = path;
    LocalStorageService.instance.setValue("audio_save_path", path);
  }

  void setLogEnable(bool enable) {
    logEnable.value = enable;
    LocalStorageService.instance.setValue("log_enable", enable);
  }

  void setMaxConcurrentRecordings(int max) {
    maxConcurrentRecordings.value = max;
    LocalStorageService.instance.setValue("max_concurrent_recordings", max);
  }

  void setIsDynamic(bool value) {
    isDynamic.value = value;
    LocalStorageService.instance.setValue("is_dynamic", value);
  }

  void setStyleColor(int color) {
    styleColor.value = color;
    LocalStorageService.instance.setValue("style_color", color);
  }

  void setAutoSaveToFolder(bool value) {
    autoSaveToFolder.value = value;
    LocalStorageService.instance.setValue("auto_save_to_folder", value);
  }

  void setLiveNotificationEnabled(bool value) {
    liveNotificationEnabled.value = value;
    LocalStorageService.instance.setValue("live_notification_enabled", value);
    EventBus.instance.emit(Constant.kPinnedFollowChanged, null);
  }

  void setLivePollInterval(int minutes) {
    final clamped = minutes.clamp(1, 60);
    livePollInterval.value = clamped;
    LocalStorageService.instance.setValue("live_poll_interval", clamped);
    EventBus.instance.emit(Constant.kPinnedFollowChanged, null);
  }

  void setAutoRecordPinned(bool value) {
    autoRecordPinned.value = value;
    LocalStorageService.instance.setValue("auto_record_pinned", value);
  }

  void setAudioFormat(String format) {
    audioFormat.value = format;
    LocalStorageService.instance.setValue("audio_format", format);
  }

  void setDeleteTsAfterUnpack(bool value) {
    deleteTsAfterUnpack.value = value;
    LocalStorageService.instance.setValue("delete_ts_after_unpack", value);
  }

  void setAutoSliceEnabled(bool value) {
    autoSliceEnabled.value = value;
    LocalStorageService.instance.setValue("auto_slice_enabled", value);
  }

  void setAutoSliceIntervalMinutes(int minutes) {
    final clamped = minutes.clamp(1, 240);
    autoSliceIntervalMinutes.value = clamped;
    LocalStorageService.instance.setValue("auto_slice_interval", clamped);
  }

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

  void setLiveCheckConcurrency(int limit) {
    final clamped = limit.clamp(5, 50);
    liveCheckConcurrency.value = clamped;
    LocalStorageService.instance.setValue("live_check_concurrency", clamped);
  }
}
