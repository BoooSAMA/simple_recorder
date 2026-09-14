import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';

/// 全应用统一的弹出消息出口
///
/// 所有 Get.snackbar / SmartDialog.showToast 都走这里，
/// 显示时长统一受设置「弹出消息停留时长」控制。
/// 调用处若显式传入 duration/displayTime 则尊重调用处的值。
class AppNotify {
  static Duration get _defaultDuration => Duration(
        seconds: AppSettingsController.instance.popupDurationSeconds.value,
      );

  /// 顶部/底部横幅消息（替代 Get.snackbar）
  static void snackbar(
    String title,
    String message, {
    SnackPosition? snackPosition,
    Duration? duration,
    TextButton? mainButton,
    double? maxWidth,
  }) {
    Get.snackbar(
      title,
      message,
      snackPosition: snackPosition ?? SnackPosition.BOTTOM,
      duration: duration ?? _defaultDuration,
      mainButton: mainButton,
      maxWidth: maxWidth,
    );
  }

  /// 轻量 Toast（替代 SmartDialog.showToast）
  static Future<void> toast(
    String msg, {
    Duration? displayTime,
  }) {
    return SmartDialog.showToast(
      msg,
      displayTime: displayTime ?? _defaultDuration,
    );
  }
}
