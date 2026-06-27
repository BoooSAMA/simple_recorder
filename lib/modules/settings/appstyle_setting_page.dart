import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';
import 'package:simple_recorder/widgets/settings/settings_switch.dart';

class AppstyleSettingPage extends GetView<AppSettingsController> {
  const AppstyleSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("外观设置")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text("显示主题", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Obx(
              () => RadioGroup<int>(
                groupValue: controller.themeMode.value,
                onChanged: (e) => controller.setThemeMode(e ?? 0),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      title: Text("跟随系统"),
                      visualDensity: VisualDensity.compact,
                      value: 0,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    RadioListTile<int>(
                      title: Text("浅色模式"),
                      visualDensity: VisualDensity.compact,
                      value: 1,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    RadioListTile<int>(
                      title: Text("深色模式"),
                      visualDensity: VisualDensity.compact,
                      value: 2,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text("主题颜色", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSwitch(
                    value: controller.isDynamic.value,
                    title: "动态取色",
                    onChanged: (e) {
                      controller.setIsDynamic(e);
                    },
                  ),
                  if (!controller.isDynamic.value) const Divider(),
                  if (!controller.isDynamic.value)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Color>[
                          const Color(0xffEF5350),
                          const Color(0xff3498db),
                          const Color(0xffF06292),
                          const Color(0xff9575CD),
                          const Color(0xff26C6DA),
                          const Color(0xff26A69A),
                          const Color(0xffFFF176),
                          const Color(0xffFF9800),
                        ]
                            .map((e) => GestureDetector(
                                  onTap: () {
                                    controller.setStyleColor(e.toARGB32());
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: e,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.grey.withAlpha(50),
                                        width: 1,
                                      ),
                                    ),
                                    child: Obx(() => Center(
                                          child: Icon(
                                            Icons.check,
                                            color: controller
                                                        .styleColor.value ==
                                                    e.toARGB32()
                                                ? Colors.white
                                                : Colors.transparent,
                                          ),
                                        )),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
