import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/recording_service.dart';

class LiveNotificationService {
  static final LiveNotificationService _instance = LiveNotificationService._();
  static LiveNotificationService get instance => _instance;
  LiveNotificationService._();

  FlutterLocalNotificationsPlugin? _plugin;
  final Set<String> _notifiedLiveIds = {};
  int _keepAliveCount = 0;

  Future<void> init() async {
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

  /// 通知主播开播（系统通知栏推送）
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
  }

  /// 主播下播后清除去重记录，允许下次开播时重新通知
  void clearNotified(String id) {
    _notifiedLiveIds.remove(id);
  }

  /// 获取前台服务保活（计数引用，避免 poller 被系统杀死）
  Future<void> acquireKeepAlive() async {
    if (_keepAliveCount == 0) {
      await RecordingSession.acquireForegroundService();
      // 更新前台服务通知内容，提示用户保活原因
      try {
        FlutterBackgroundService().invoke('update', {
          'title': 'Simple Recorder',
          'content': '开播通知服务运行中',
        });
      } catch (_) {}
    }
    _keepAliveCount++;
  }

  /// 释放前台服务保活
  Future<void> releaseKeepAlive() async {
    if (_keepAliveCount <= 0) return;
    _keepAliveCount--;
    if (_keepAliveCount == 0) {
      await RecordingSession.releaseForegroundService();
    }
  }

  /// 释放资源
  void dispose() {}
}
