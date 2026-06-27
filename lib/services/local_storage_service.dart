import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalStorageService extends GetxService {
  static LocalStorageService get instance => Get.find<LocalStorageService>();

  late Box _box;

  Future<void> init() async {
    _box = await Hive.openBox("settings");
  }

  dynamic getValue(String key, [dynamic defaultValue]) {
    return _box.get(key, defaultValue: defaultValue);
  }

  Future<void> setValue(String key, dynamic value) async {
    await _box.put(key, value);
  }

  Future<void> removeValue(String key) async {
    await _box.delete(key);
  }
}
