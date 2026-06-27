import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/follow_export_service.dart';
import 'package:simple_recorder/widgets/settings/settings_action.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    var controller = AppSettingsController.instance;

    return Scaffold(
      appBar: AppBar(title: const Text("设置")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionTitle("录制"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(() => SwitchListTile(
                      title: const Text("按主播名自动创建文件夹"),
                      subtitle: const Text("保存时自动存进主播名称的文件夹"),
                      value: controller.autoSaveToFolder.value,
                      onChanged: (v) => controller.setAutoSaveToFolder(v),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle("存储"),
          SettingsCard(
            child: SettingsAction(
              title: "音频存储路径",
              value: controller.audioSavePath.value.isNotEmpty
                  ? controller.audioSavePath.value
                  : "默认路径",
              onTap: () => Get.toNamed(RoutePath.kAudioSettings),
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle("界面"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsAction(
                  title: "外观设置",
                  leading: const Icon(Icons.palette_outlined),
                  onTap: () => Get.toNamed(RoutePath.kAppStyleSetting),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle("数据"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsAction(
                  title: "导出关注列表",
                  leading: const Icon(Icons.file_upload_outlined),
                  onTap: () => FollowExportService.exportFollowData(),
                ),
                const Divider(height: 1, indent: 16),
                SettingsAction(
                  title: "导入关注列表",
                  leading: const Icon(Icons.file_download_outlined),
                  onTap: () => FollowExportService.importFollowData(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle("调试"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsAction(
                  title: "查看调试日志",
                  leading: const Icon(Icons.bug_report_outlined),
                  onTap: () => Get.toNamed(RoutePath.kDebugLog),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionTitle("关于"),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final version = snapshot.hasData
                        ? snapshot.data!.version
                        : "...";
                    return ListTile(
                      title: const Text("版本"),
                      trailing: Text(version),
                    );
                  },
                ),
                const ListTile(
                  title: Text("开源协议"),
                  trailing: Text("GPLv3"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.all(12).copyWith(top: 0),
      child: Text(title, style: Get.textTheme.titleSmall),
    );
  }
}
