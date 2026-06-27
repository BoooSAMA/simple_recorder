import 'package:get/get.dart';
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

  @override
  void onInit() {
    super.onInit();
    loadSettings();
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
  }

  void setThemeMode(int mode) {
    themeMode.value = mode;
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
}
