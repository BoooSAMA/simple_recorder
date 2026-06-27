import 'package:get/get.dart';
import 'package:simple_recorder/modules/home/home_page.dart';
import 'package:simple_recorder/modules/search/search_page.dart';
import 'package:simple_recorder/modules/settings/settings_page.dart';
import 'package:simple_recorder/modules/settings/appstyle_setting_page.dart';
import 'package:simple_recorder/modules/settings/audio_settings_page.dart';
import 'package:simple_recorder/modules/other/debug_log_page.dart';
import 'package:simple_recorder/routes/route_path.dart';

class AppPages {
  static final routes = [
    GetPage(
      name: RoutePath.kIndex,
      page: () => const HomePage(),
    ),
    GetPage(
      name: RoutePath.kSearch,
      page: () => const SearchPage(),
    ),
    GetPage(
      name: RoutePath.kSettings,
      page: () => const SettingsPage(),
    ),
    GetPage(
      name: RoutePath.kAppStyleSetting,
      page: () => const AppstyleSettingPage(),
    ),
    GetPage(
      name: RoutePath.kAudioSettings,
      page: () => const AudioSettingsPage(),
    ),
    GetPage(
      name: RoutePath.kDebugLog,
      page: () => const DebugLogPage(),
    ),
  ];
}
