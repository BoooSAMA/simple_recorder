import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/design_tokens.dart';
import 'package:simple_recorder/modules/recordings/floating_audio_player.dart';
import 'package:simple_recorder/modules/recordings/recordings_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/global_player_controller.dart';
import 'package:simple_recorder/widgets/icon_tile.dart';
import 'package:simple_recorder/widgets/status_badge.dart';

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
          return _buildPlaceholder(
            context,
            icon: Icons.folder_off_outlined,
            title: "请先设置音频存储路径",
            subtitle: "录音会按主播分文件夹保存到你选择的位置",
            action: FilledButton.icon(
              onPressed: () => Get.toNamed(RoutePath.kAudioSettings),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text("前往设置"),
            ),
          );
        }

        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.groups.isEmpty) {
          return _buildPlaceholder(
            context,
            icon: Icons.music_note_outlined,
            title: "没有发现录音文件",
            subtitle: "录制完成或解包后的音频会出现在这里",
          );
        }

        return Column(
          children: [
            _buildToolbar(context, controller),
            Expanded(child: _buildFileList(context, controller)),
            _buildSummaryBar(context, controller),
            // 全局播放器显示时顶起统计条，避免被悬浮播放器遮挡
            const PlayerAvoidanceSpace(),
          ],
        );
      }),
    );
  }

  /// 统一的空状态 / 未配置状态
  Widget _buildPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    var theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppSurface.chip(theme.colorScheme),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.xl),
              action,
            ],
          ],
        ),
      ),
    );
  }

  /// 顶部工具条：文件排序筛选 + 一键折叠/展开所有主播文件夹
  Widget _buildToolbar(BuildContext context, RecordingsController controller) {
    var theme = Theme.of(context);
    final chipFg = theme.colorScheme.onSurfaceVariant;

    Widget chip({
      required IconData icon,
      required Widget label,
      VoidCallback? onTap,
      GestureTapDownCallback? onTapDown,
    }) {
      return Material(
        color: AppSurface.chip(theme.colorScheme),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rPill,
          side: BorderSide(
            color: AppSurface.outline(theme.colorScheme),
            width: 0.6,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown,
          borderRadius: AppRadius.rPill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: chipFg),
                const SizedBox(width: 5),
                label,
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 排序筛选
          chip(
            icon: Icons.sort,
            onTapDown: (details) =>
                _showSortMenu(context, controller, details.globalPosition),
            label: Obx(
              () => Text(
                _sortModeLabel(controller.sortMode.value),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: chipFg,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const Spacer(),
          // 一键收起/展开所有主播文件夹
          Obx(() {
            var anyExpanded = false;
            for (var g in controller.groups) {
              if (g.isExpanded.value) {
                anyExpanded = true;
                break;
              }
            }
            return chip(
              icon: anyExpanded ? Icons.unfold_less : Icons.unfold_more,
              onTap: () => controller.toggleCollapseAll(),
              label: Text(
                anyExpanded ? "全部收起" : "全部展开",
                style: theme.textTheme.labelMedium?.copyWith(
                  color: chipFg,
                  fontSize: 12,
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
    BuildContext context,
    RecordingsController controller,
    Offset position,
  ) async {
    var theme = Theme.of(context);
    const labels = [
      '创建时间降序（最新在前）',
      '创建时间升序（最旧在前）',
      '主播名',
      '文件名日期降序（最新在前）',
      '文件名日期升序（最旧在前）',
    ];
    final value = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
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
        return "创建时间升序";
      case 2:
        return "主播名";
      case 3:
        return "文件名日期降序";
      case 4:
        return "文件名日期升序";
      default:
        return "创建时间降序";
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
              var allSelected =
                  isSelecting &&
                  group.items.isNotEmpty &&
                  group.items.every((item) => item.isSelected.value);
              return Material(
                color: isSelecting && allSelected
                    ? theme.colorScheme.primary.withAlpha(18)
                    : AppSurface.header(theme.colorScheme),
                child: InkWell(
                  onTap: () => controller.toggleGroup(groupIndex),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor,
                          width: 0.5,
                        ),
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
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          Icon(
                            Icons.folder_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            group.folderName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StatusBadge(
                          "${group.count} 个",
                          tone: StatusTone.neutral,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: AppMotion.normal,
                          curve: AppMotion.standard,
                          child: Icon(
                            Icons.expand_more,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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
                    context,
                    controller,
                    item,
                    i,
                    items.length,
                    items,
                  );
                }).toList(),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildFileRow(
    BuildContext context,
    RecordingsController controller,
    RecordingItem item,
    int index,
    int total,
    List<RecordingItem> siblings,
  ) {
    var theme = Theme.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (controller.isSelectMode.value) {
          controller.toggleSelection(item);
        } else {
          // 切换播放文件（同组文件作为播放队列，用于上下首/自动连播）
          GlobalPlayerController.instance.playFile(
            item.path,
            item.fileName,
            queue: siblings.map((e) => QueueTrack(e.path, e.fileName)).toList(),
            index: index,
          );
        }
      },
      child: Obx(() {
        var isSelecting = controller.isSelectMode.value;
        var isSelected = item.isSelected.value;
        var isCurrentlyPlaying =
            GlobalPlayerController.instance.currentPath.value == item.path;

        final rowColor = isCurrentlyPlaying
            ? theme.colorScheme.primary.withAlpha(12)
            : isSelecting && isSelected
            ? theme.colorScheme.primary.withAlpha(15)
            : Colors.transparent;

        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.fromLTRB(13, 8, 16, 8),
          decoration: BoxDecoration(
            color: rowColor,
            border: Border(
              left: BorderSide(
                color: isCurrentlyPlaying
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 3,
              ),
              bottom: index < total - 1
                  ? BorderSide(color: theme.dividerColor, width: 0.3)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              if (isSelecting)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    isSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 20,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AppIconTile(
                    icon: Icons.graphic_eq_rounded,
                    size: 28,
                    iconSize: 16,
                    color: isCurrentlyPlaying
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.fileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isCurrentlyPlaying
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              if (!isSelecting)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    isCurrentlyPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_outline_rounded,
                    size: 22,
                    color: isCurrentlyPlaying
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSummaryBar(
    BuildContext context,
    RecordingsController controller,
  ) {
    var theme = Theme.of(context);
    var bottomInset = MediaQuery.of(context).padding.bottom;
    final strong = TextStyle(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 0.5)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: "共 "),
            TextSpan(text: "${controller.totalFolders}", style: strong),
            const TextSpan(text: " 个主播 · "),
            TextSpan(text: "${controller.totalFiles}", style: strong),
            const TextSpan(text: " 个录音文件"),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 11.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
