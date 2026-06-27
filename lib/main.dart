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

  initCoreLog();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  runApp(const MyApp());
}

void _requestPermissions() {
  // 不阻塞启动，fire-and-forget
  Future(() async {
    // 请求管理所有文件权限 (Android 11+ 必需)
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  });
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
