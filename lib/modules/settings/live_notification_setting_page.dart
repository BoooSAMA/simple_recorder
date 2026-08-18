import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';

class LiveNotificationSettingPage extends StatelessWidget {
  const LiveNotificationSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = AppSettingsController.instance;
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("开播通知")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(() => SwitchListTile(
                      title: const Text("开播通知"),
                      subtitle: const Text("Pin 的主播开播时推送系统通知"),
                      value: controller.liveNotificationEnabled.value,
                      onChanged: (v) =>
                          controller.setLiveNotificationEnabled(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => _PollIntervalTile(
                      minutes: controller.livePollInterval.value,
                      onChanged: (v) => controller.setLivePollInterval(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("置顶主播开播时自动录制"),
                      subtitle: const Text("轮询检测到 pin 主播开播后自动开始录制"),
                      value: controller.autoRecordPinned.value,
                      onChanged: (v) =>
                          controller.setAutoRecordPinned(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("非 Pin 主播开播通知"),
                      subtitle: const Text("轮询检测到非置顶主播开播时也推送系统通知"),
                      value: controller.notifyNonPinnedLive.value,
                      onChanged: (v) =>
                          controller.setNotifyNonPinnedLive(v),
                    )),
                const Divider(height: 1, indent: 16),
                Obx(() => SwitchListTile(
                      title: const Text("后台自动刷新非 Pin 主播状态"),
                      subtitle: const Text("后台轮询时同步刷新非置顶主播的直播状态"),
                      value: controller.backgroundRefreshNonPinned.value,
                      onChanged: (v) =>
                          controller.setBackgroundRefreshNonPinned(v),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "后台轮询间隔：每 N 分钟检测一次置顶主播的直播状态，"
              "检测到开播时发送通知。开启\"非 Pin 开播通知\"或"
              "\"后台自动刷新\"后，非置顶主播也会被轮询检测。"
              "间隔越短通知越及时，但耗电也越多。",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(100),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PollIntervalTile extends StatelessWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  const _PollIntervalTile({
    required this.minutes,
    required this.onChanged,
  });

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: minutes.toString());
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("设置轮询间隔"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "间隔（分钟）",
            suffixText: "分钟",
            helperText: "范围：1 ~ 60",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed != null) {
                Navigator.of(ctx).pop(parsed.clamp(1, 60));
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    ).then((v) {
      if (v != null) onChanged(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text("后台轮询间隔",
                style: theme.textTheme.bodyLarge),
          ),
          _RoundButton(
            icon: Icons.remove,
            onTap: () => onChanged(minutes - 1),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showEditDialog(context),
            child: Container(
              width: 48,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withAlpha(80),
                ),
              ),
              child: Text(
                "$minutes",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RoundButton(
            icon: Icons.add,
            onTap: () => onChanged(minutes + 1),
          ),
          const SizedBox(width: 8),
          Text("分钟",
              style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18),
      ),
    );
  }
}
