import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/modules/recordings/audio_player_sheet.dart';
import 'package:simple_recorder/modules/recordings/recordings_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';

class RecordingsPage extends StatelessWidget {
  const RecordingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(RecordingsController());
    var theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BackButton(),
            GestureDetector(
              onTap: () => Get.offNamed(RoutePath.kTsUnpack),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.unarchive_outlined, size: 20),
              ),
            ),
          ],
        ),
        title: const Text("录音文件"),
        actions: [
          Obx(() {
            if (controller.isSelectMode.value) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 删除
                  GestureDetector(
                    onTap: controller.selectedCount > 0
                        ? () => controller.deleteSelected()
                        : null,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: controller.selectedCount > 0
                            ? Colors.red
                            : theme.colorScheme.onSurface.withAlpha(60),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  // 取消选择
                  GestureDetector(
                    onTap: () => controller.toggleSelectMode(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.close, size: 20),
                    ),
                  ),
                ],
              );
            }
            // 正常模式：选择入口
            return GestureDetector(
              onTap: () => controller.toggleSelectMode(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.checklist, size: 20),
              ),
            );
          }),
          // 刷新
          GestureDetector(
            onTap: () => controller.scanDirectory(),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.refresh, size: 20),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        if (!controller.hasSavePath.value) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text("请先设置音频存储路径",
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.outline)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Get.toNamed(RoutePath.kAudioSettings),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text("前往设置"),
                  ),
                ],
              ),
            ),
          );
        }

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_outlined,
                    size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text("没有发现录音文件",
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Expanded(child: _buildFileList(context, controller)),
            _buildSummaryBar(context, controller),
          ],
        );
      }),
    );
  }

  Widget _buildFileList(BuildContext context, RecordingsController controller) {
    var theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: controller.groups.length,
      itemBuilder: (context, groupIndex) {
        var group = controller.groups[groupIndex];
        var items = group.items;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分组表头
            Obx(() {
              var isExpanded = group.isExpanded.value;
              return InkWell(
                onTap: () => controller.toggleGroup(groupIndex),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(60),
                    border: Border(
                      bottom: BorderSide(
                          color: theme.dividerColor, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          group.folderName,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        "${group.count}个文件",
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withAlpha(150)),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ],
                  ),
                ),
              );
            }),

            // 文件列表
            Obx(() {
              if (!group.isExpanded.value) {
                return const SizedBox.shrink();
              }
              return Column(
                children: items.asMap().entries.map((entry) {
                  var i = entry.key;
                  var item = entry.value;
                  return _buildFileRow(
                      context, controller, item, i, items.length);
                }).toList(),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildFileRow(BuildContext context, RecordingsController controller,
      RecordingItem item, int index, int total) {
    var theme = Theme.of(context);
    return InkWell(
      onTap: () {
        if (controller.isSelectMode.value) {
          controller.toggleSelection(item);
        } else {
          ShowAudioPlayerSheet.show(
            context,
            filePath: item.path,
            fileName: item.fileName,
          );
        }
      },
      child: Obx(() {
        var isSelected = item.isSelected.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: controller.isSelectMode.value && isSelected
                ? theme.colorScheme.primary.withAlpha(15)
                : null,
            border: index < total - 1
                ? Border(
                    bottom: BorderSide(
                        color: theme.dividerColor, width: 0.3))
                : null,
          ),
          child: Row(
            children: [
              if (controller.isSelectMode.value)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha(100),
                  ),
                )
              else
                const Icon(Icons.audiotrack, size: 18, color: Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.fileName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${item.fileSize} · ${item.lastModified}",
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withAlpha(100)),
                    ),
                  ],
                ),
              ),
              if (!controller.isSelectMode.value)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.play_circle_outline,
                      size: 18, color: Colors.blue),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSummaryBar(
      BuildContext context, RecordingsController controller) {
    var theme = Theme.of(context);
    var bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Text(
        "共 ${controller.totalFolders} 个主播，${controller.totalFiles} 个录音文件",
        style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(150)),
        textAlign: TextAlign.center,
      ),
    );
  }
}
