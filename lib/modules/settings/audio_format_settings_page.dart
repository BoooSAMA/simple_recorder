import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';

class AudioFormatSettingsPage extends StatelessWidget {
  const AudioFormatSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = AppSettingsController.instance;
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("音频输出格式")),
      body: Obx(() {
        var currentFormat = controller.audioFormat.value;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                "录制完成后，自动将 TS 文件转换为此格式",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(150),
                ),
              ),
            ),
            Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: Constant.kSupportedAudioFormats.map((format) {
                  var isSelected = currentFormat == format;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (format != Constant.kSupportedAudioFormats.first)
                        const Divider(height: 1, indent: 16),
                      RadioListTile<String>(
                        title: Row(
                          children: [
                            Text(
                              Constant.audioFormatDisplayName(format),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (format == Constant.kAudioFormatM4A)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "推荐",
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          Constant.audioFormatDescription(format),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                        value: format,
                        groupValue: currentFormat,
                        onChanged: (v) {
                          if (v != null) {
                            controller.setAudioFormat(v);
                          }
                        },
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                "提示：M4A 格式直接从 TS 中复制音频流，不重编码，速度最快且质量无损。"
                "其他格式需要重编码，速度较慢且可能有质量损失。"
                "更改设置仅影响后续录制，不影响已存在的录制文件。",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(100),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
