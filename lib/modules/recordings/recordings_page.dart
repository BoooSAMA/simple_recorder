import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/modules/recordings/floating_audio_player.dart';
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
            InkWell(
              onTap: () => Get.offNamed(RoutePath.kTsUnpack),
              borderRadius: BorderRadius.circular(20),
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
          InkWell(
            onTap: () => controller.scanDirectory(),
            borderRadius: BorderRadius.circular(20),
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
            _buildToolbar(context, controller),
            Expanded(child: _buildFileList(context, controller)),
            _buildMiniPlayer(context, controller),
            _buildSummaryBar(context, controller),
          ],
        );
      }),
    );
  }

  /// 顶部工具条：文件排序筛选 + 一键折叠/展开所有主播文件夹
  Widget _buildToolbar(BuildContext context, RecordingsController controller) {
    var theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 排序筛选
          InkWell(
            onTapDown: (details) =>
                _showSortMenu(context, controller, details.globalPosition),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 4),
                  Obx(() => Text(
                        _sortModeLabel(controller.sortMode.value),
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface
                                .withAlpha(150)),
                      )),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 一键收起/展开所有主播文件夹
          Obx(() {
            // 订阅所有分组的展开状态，驱动按钮图标切换
            var anyExpanded = false;
            for (var g in controller.groups) {
              if (g.isExpanded.value) {
                anyExpanded = true;
                break;
              }
            }
            return InkWell(
              onTap: () => controller.toggleCollapseAll(),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      anyExpanded ? Icons.unfold_less : Icons.unfold_more,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      anyExpanded ? "全部收起" : "全部展开",
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withAlpha(150)),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 弹出排序方式选择菜单
  Future<void> _showSortMenu(
      BuildContext context, RecordingsController controller, Offset position) async {
    var theme = Theme.of(context);
    const labels = ['日期降序（最新在前）', '日期升序（最旧在前）', '主播名'];
    final value = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        for (var m = 0; m < labels.length; m++)
          PopupMenuItem(
            value: m,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller.sortMode.value == m
                      ? Icons.check
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: controller.sortMode.value == m
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withAlpha(100),
                ),
                const SizedBox(width: 8),
                Text(labels[m], style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
    if (value != null) controller.setSortMode(value);
  }

  String _sortModeLabel(int mode) {
    switch (mode) {
      case 1:
        return "日期升序";
      case 2:
        return "主播名";
      default:
        return "日期降序";
    }
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
              var isSelecting = controller.isSelectMode.value;
              var allSelected = isSelecting &&
                  group.items.isNotEmpty &&
                  group.items.every((item) => item.isSelected.value);
              return InkWell(
                onTap: () => controller.toggleGroup(groupIndex),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelecting && allSelected
                        ? theme.colorScheme.primary.withAlpha(12)
                        : theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                    border: Border(
                      bottom: BorderSide(
                          color: theme.dividerColor, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (isSelecting)
                        GestureDetector(
                          onTap: () =>
                              controller.toggleGroupSelection(groupIndex),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(
                              allSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 20,
                              color: allSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface
                                      .withAlpha(100),
                            ),
                          ),
                        )
                      else
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
          // 切换播放文件（浮动播放器自动响应加载并播放）
          controller.setCurrentlyPlaying(item.path, item.fileName);
        }
      },
      child: Obx(() {
        var isSelected = item.isSelected.value;
        var isCurrentlyPlaying =
            controller.currentlyPlayingPath.value == item.path;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrentlyPlaying
                ? theme.colorScheme.primary.withAlpha(20)
                : controller.isSelectMode.value && isSelected
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
                    Obx(() {
                      var dur = item.duration.value;
                      var info = "${item.fileSize} · ${item.lastModified}";
                      if (dur.isNotEmpty) info += " · $dur";
                      return Text(
                        info,
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withAlpha(100)),
                      );
                    }),
                  ],
                ),
              ),
              if (!controller.isSelectMode.value)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Obx(() {
                    var isPlaying =
                        controller.currentlyPlayingPath.value == item.path;
                    return Icon(
                      isPlaying
                          ? Icons.play_circle
                          : Icons.play_circle_outline,
                      size: 18,
                      color: isPlaying
                          ? theme.colorScheme.primary
                          : Colors.blue,
                    );
                  }),
                ),
            ],
          ),
        );
      }),
    );
  }

  /// 底部浮动胶囊迷你播放器（有播放文件时显示，不遮挡文件列表交互）
  Widget _buildMiniPlayer(
      BuildContext context, RecordingsController controller) {
    return Obx(() {
      var path = controller.currentlyPlayingPath.value;
      if (path.isEmpty) return const SizedBox.shrink();
      return FloatingAudioPlayer(
        key: ValueKey(path),
        filePath: path,
        fileName: controller.currentlyPlayingName.value,
        onClose: () => controller.clearCurrentlyPlaying(),
      );
    });
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
