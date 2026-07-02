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
  /// 系统通知：始终发送
  /// SnackBar：仅在前台时显示
  Future<void> notifyLiveStart(FollowUser user) async {
    if (_notifiedLiveIds.contains(user.id)) return;
    _notifiedLiveIds.add(user.id);

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

    if (_appInForeground) {
      Get.snackbar(
        '开播提醒',
        '${user.userName} 开播了！',
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 4),
        backgroundColor: Get.theme.colorScheme.primaryContainer,
        colorText: Get.theme.colorScheme.onPrimaryContainer,
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
