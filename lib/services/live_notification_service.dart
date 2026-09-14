import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/app/sites.dart';
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
  ///
  /// 按设置决定信息量：默认标题行 `{主播} 开播了！`；
  /// 开启后正文可附带直播间标题与已开播时长（需调一次房间详情接口，
  /// 失败时降级为默认通知，不影响推送本身）。
  Future<void> notifyLiveStart(FollowUser user) async {
    if (_notifiedLiveIds.contains(user.id)) return;
    _notifiedLiveIds.add(user.id);

    var body = '点击查看直播间';
    try {
      final settings = AppSettingsController.instance;
      final withTitle = settings.notifyWithTitle.value;
      final withDuration = settings.notifyWithDuration.value;
      if (withTitle || withDuration) {
        final site = Sites.getSite(user.siteId);
        final detail =
            await site?.liveSite.getRoomDetail(roomId: user.roomId);
        if (detail != null && detail.status) {
          final extras = <String>[];
          if (withTitle && detail.title.isNotEmpty) {
            extras.add(detail.title);
          }
          final showTime = detail.showTime;
          if (withDuration && showTime != null && showTime.isNotEmpty) {
            final elapsed = _formatElapsed(showTime);
            if (elapsed != null) extras.add('已开播 $elapsed');
          }
          if (extras.isNotEmpty) {
            body = '$body\n${extras.join('\n')}';
          }
        }
      }
    } catch (e) {
      Log.logPrint("获取开播详情失败，使用默认通知内容: $e");
    }

    try {
      await _plugin?.show(
        user.id.hashCode.abs(),
        '${user.userName} 开播了！',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'live_notification',
            '开播提醒',
            channelDescription: 'Pin 的主播开播时发送通知',
            importance: Importance.high,
            priority: Priority.high,
            // 正文多行时展开显示
            styleInformation: BigTextStyleInformation(''),
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

  /// showTime（秒时间戳）→ 精简已播时长，如 "2小时15分" / "35分钟" / "刚刚"
  String? _formatElapsed(String showTime) {
    try {
      final start = int.parse(showTime);
      var diff = DateTime.now().millisecondsSinceEpoch ~/ 1000 - start;
      if (diff < 0) return null;
      if (diff < 60) return '刚刚';
      final h = diff ~/ 3600;
      final m = (diff % 3600) ~/ 60;
      if (h > 0) return '$h小时$m分';
      return '$m分钟';
    } catch (_) {
      return null;
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
