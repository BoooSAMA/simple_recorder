import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/follow_export_service.dart';
import 'package:simple_recorder/widgets/settings/settings_action.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';
import 'package:simple_recorder/widgets/settings/settings_number.dart';

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
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("按主播名自动创建文件夹"),
                      subtitle: const Text("保存时自动存进主播名称的文件夹"),
                      value: controller.autoSaveToFolder.value,
                      onChanged: (v) => controller.setAutoSaveToFolder(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SettingsNumber(
                      title: "直播状态检测并发数",
                      value: controller.liveCheckConcurrency.value,
                      min: 5,
                      max: 50,
                      step: 5,
                      unit: " 路",
                      displayValue: "${controller.liveCheckConcurrency.value} 路",
                      subtitle: "同时检测的直播间数量 (5~50)，越高越快但更耗流量",
                      showTextInput: true,
                      onChanged: (v) =>
                          controller.setLiveCheckConcurrency(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SettingsAction(
                      title: "音频输出格式",
                      value: Constant.audioFormatDisplayName(
                          controller.audioFormat.value),
                      onTap: () => Get.toNamed(RoutePath.kAudioFormat),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("解包后删除 TS 文件"),
                      subtitle: const Text("转换完成后自动删除中间 TS 文件"),
                      value: controller.deleteTsAfterUnpack.value,
                      onChanged: (v) =>
                          controller.setDeleteTsAfterUnpack(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("自动切片录制"),
                      subtitle: const Text("按设定间隔自动切分并解包 TS 文件"),
                      value: controller.autoSliceEnabled.value,
                      onChanged: (v) =>
                          controller.setAutoSliceEnabled(v),
                    )),
                Obx(() {
                  var enabled = controller.autoSliceEnabled.value;
                  var interval = controller.autoSliceIntervalMinutes.value;
                  return Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "切片间隔",
                        value: interval,
                        min: 1,
                        max: 240,
                        step: 10,
                        unit: " 分钟",
                        displayValue: "$interval 分钟",
                        subtitle: "范围 1~240 分钟",
                        onChanged: enabled
                            ? (v) =>
                                controller.setAutoSliceIntervalMinutes(v)
                            : null,
                      ),
                    ),
                  );
                }),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("直播恢复自动续录"),
                      subtitle: const Text("直播结束后自动检测主播是否重新开播并恢复录制"),
                      value: controller.autoReRecordEnabled.value,
                      onChanged: (v) =>
                          controller.setAutoReRecordEnabled(v),
                    )),
                Obx(() {
                  var enabled = controller.autoReRecordEnabled.value;
                  var delay = controller.autoReRecordDelayMinutes.value;
                  return Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "检测间隔",
                        value: delay,
                        min: 1,
                        max: 30,
                        step: 1,
                        unit: " 分钟",
                        displayValue: "$delay 分钟",
                        subtitle: "直播断开后多久检测一次 (1~30)",
                        onChanged: enabled
                            ? (v) =>
                                controller.setAutoReRecordDelayMinutes(v)
                            : null,
                      ),
                    ),
                  );
                }),
                Obx(() {
                  var enabled = controller.autoReRecordEnabled.value;
                  var retries = controller.autoReRecordMaxRetries.value;
                  return Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "最大检测次数",
                        value: retries,
                        min: 1,
                        max: 10,
                        step: 1,
                        unit: " 次",
                        displayValue: "$retries 次",
                        subtitle: "最多检测几次后放弃 (1~10)",
                        onChanged: enabled
                            ? (v) =>
                                controller.setAutoReRecordMaxRetries(v)
                            : null,
                      ),
                    ),
                  );
                }),
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
