import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_recorder/app/app_style.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/models/db/recording_task.dart';
import 'package:simple_recorder/routes/app_pages.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_recorder/services/local_storage_service.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:simple_recorder/services/live_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(FollowUserAdapter());
  Hive.registerAdapter(RecordingTaskAdapter());

  await Get.put(LocalStorageService()).init();
  await Get.put(DBService()).init();

  Get.put(AppSettingsController());
  Get.put(RecordingManager());

  // 新用户首启：请求通知权限和存储权限
  _requestPermissions();
  LiveNotificationService.instance.init();

  // 扫描并标记异常中断的 TS 文件
  _markInterruptedFiles();

  initCoreLog();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  // 初始化前台服务，防止系统杀死后台录制进程
  try {
    await _initForegroundService();
  } catch (e) {
    Log.logPrint("前台服务初始化失败（可能在不支持的平台上）: $e");
  }

  runApp(const MyApp());
}

/// 扫描音频目录，将异常中断的 TS 文件（无结束时间段）标记为 _interrupted
void _markInterruptedFiles() {
  Future(() async {
    var savePath = AppSettingsController.instance.audioSavePath.value;
    if (savePath.isEmpty) return;

    var rootDir = Directory(savePath);
    if (!await rootDir.exists()) return;

    // 已完成格式: {name}_{date}_{start}_{end}.ts
    final completedRegex =
        RegExp(r'_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}_\d{2}-\d{2}\.ts$');
    // App 创建的文件含日期时间
    final appFileRegex = RegExp(r'_\d{4}-\d{2}-\d{2}_\d{2}');

    try {
      await for (var entity in rootDir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.ts')) continue;

        var name = entity.path.split('/').last;

        // 跳过已完成或已标记的文件
        if (completedRegex.hasMatch(name)) continue;
        if (name.contains('_interrupted')) continue;

        // 非 App 命名的文件不处理
        if (!appFileRegex.hasMatch(name)) continue;

        // 标记为中断文件
        var newPath = entity.path.replaceAll('.ts', '_interrupted.ts');
        await entity.rename(newPath);
        Log.logPrint("标记中断文件: $name → ${newPath.split('/').last}");
      }
    } catch (e) {
      Log.logPrint("扫描中断文件失败: $e");
    }
  });
}

void _requestPermissions() {
  // 不阻塞启动，fire-and-forget
  Future(() async {
    // 请求管理所有文件权限 (Android 11+ 必需)
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  });
}

/// 初始化前台录制服务，接收来自 Flutter 的消息并展示通知
Future<void> _initForegroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onForegroundServiceStart,
      autoStart: false,
      isForegroundMode: true,
      initialNotificationContent: "Simple Recorder 录制服务就绪",
      initialNotificationTitle: "Simple Recorder",
      notificationChannelId: "simple_recorder_channel",
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onForegroundServiceStart,
      onBackground: _onForegroundServiceStart,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> _onForegroundServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Simple Recorder",
      content: "录制服务就绪",
    );

    // 允许 Flutter 层通过 sendData 来更新通知内容
    service.on("update").listen((event) {
      if (event != null) {
        final data = event;
        if (data.containsKey("title")) {
          service.setForegroundNotificationInfo(
            title: data["title"].toString(),
            content: data["content"].toString(),
          );
        }
      }
    });
  }
  return true;
}

void initCoreLog() {
  CoreLog.enableLog = true;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, msg) {
    Log.logPrint(msg);
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    var settings = AppSettingsController.instance;

    return GetMaterialApp(
      title: "Simple Recorder",
      theme: AppStyle.lightTheme,
      darkTheme: AppStyle.darkTheme,
      themeMode: ThemeMode.values[settings.themeMode.value],
      initialRoute: RoutePath.kIndex,
      getPages: AppPages.routes,
      locale: const Locale("zh", "CN"),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale("zh", "CN")],
      defaultTransition: Transition.cupertino,
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(
        builder: (context, child) {
          var mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.0),
            ),
            child: child!,
          );
        },
      ),
    );
  }
}
