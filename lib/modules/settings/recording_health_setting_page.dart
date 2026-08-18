import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';
import 'package:simple_recorder/widgets/settings/settings_number.dart';

/// 录制状态检测设置页：定时检查录制文件是否正常写入，停滞时自动重启
class RecordingHealthSettingPage extends StatelessWidget {
  const RecordingHealthSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = AppSettingsController.instance;
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("录制状态检测")),
      body: Obx(() {
        var enabled = controller.recordingStatusCheckEnabled.value;
        var autoRestart = controller.recordingStallAutoRestart.value;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "定时检查录制文件是否在正常写入。服务器限流或断流时 "
                "FFmpeg 可能无限重连，文件长时间不增长（如始终 0KB）。",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
            SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("检测录制状态"),
                    subtitle: const Text("定时检查录制文件大小是否正常增长"),
                    value: enabled,
                    onChanged: (v) =>
                        controller.setRecordingStatusCheckEnabled(v),
                  ),
                  const Divider(height: 1, indent: 16),
                  Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "检测间隔",
                        value: controller.recordingStatusCheckInterval.value,
                        min: 10,
                        max: 300,
                        step: 10,
                        unit: " 秒",
                        displayValue:
                            "${controller.recordingStatusCheckInterval.value} 秒",
                        subtitle: "每隔多久检查一次文件大小 (10~300 秒)",
                        onChanged: enabled
                            ? (v) => controller
                                .setRecordingStatusCheckInterval(v)
                            : null,
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16),
                  Opacity(
                    opacity: enabled ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: SettingsNumber(
                        title: "停滞阈值",
                        value: controller.recordingStallThreshold.value,
                        min: 30,
                        max: 600,
                        step: 10,
                        unit: " 秒",
                        displayValue:
                            "${controller.recordingStallThreshold.value} 秒",
                        subtitle: "录制超过该时长文件仍无增长，视为停滞 (30~600 秒)",
                        onChanged: enabled
                            ? (v) => controller.setRecordingStallThreshold(v)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SettingsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text("自动重启录制"),
                    subtitle: const Text("检测到停滞时自动重启录制（重新获取播放地址）"),
                    value: autoRestart,
                    onChanged: (v) => controller.setRecordingStallAutoRestart(v),
                  ),
                  const Divider(height: 1, indent: 16),
                  Opacity(
                    opacity: enabled && autoRestart ? 1.0 : 0.4,
                    child: AbsorbPointer(
                      absorbing: !enabled || !autoRestart,
                      child: SettingsNumber(
                        title: "重启次数上限",
                        value: controller.recordingStallMaxRestarts.value,
                        min: 1,
                        max: 10,
                        step: 1,
                        unit: " 次",
                        displayValue:
                            "${controller.recordingStallMaxRestarts.value} 次",
                        subtitle: "连续停滞时最多自动重启几次后放弃 (1~10)",
                        onChanged: enabled && autoRestart
                            ? (v) => controller.setRecordingStallMaxRestarts(v)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                "停滞的文件通常没有有效内容。自动重启失败或达到上限时，"
                "会以 _interrupted 标记结束本次录制。",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}