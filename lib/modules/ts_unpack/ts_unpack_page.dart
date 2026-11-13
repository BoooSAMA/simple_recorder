import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:get/get.dart';

import 'package:simple_recorder/app/design_tokens.dart';
import 'package:simple_recorder/modules/ts_unpack/ts_unpack_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/global_player_controller.dart';
import 'package:simple_recorder/services/unpack_manager.dart'
    show kMergeGroupColors;
import 'package:simple_recorder/widgets/icon_tile.dart';
import 'package:simple_recorder/widgets/status_badge.dart';

class TsUnpackPage extends StatelessWidget {
  const TsUnpackPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(TsUnpackController());
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 96,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BackButton(),
            InkWell(
              onTap: () => Get.offNamed(RoutePath.kRecordings),
              borderRadius: BorderRadius.circular(20),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.headphones_outlined, size: 20),
              ),
            ),
          ],
        ),
        title: const Text("TS 解包工具"),
        actions: [
          InkWell(
            // 刷新 = 强制重置：卡住时先取消非录制任务、重置队列，再重扫
            onTap: () => controller.forceReset(),
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
          return _buildNoPath(context);
        }
        if (controller.groups.isEmpty) {
          return _buildEmpty(context);
        }
        return Column(
          children: [
            _buildToolbar(context, controller),
            Expanded(child: _buildFileList(context, controller)),
          ],
        );
      }),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // 全局播放器显示时，操作 pill 上移避让（收起态只需小避让）
      floatingActionButton: Obx(() {
        final c = GlobalPlayerController.instance;
        final lift = !c.isVisible ? 0 : (c.isCollapsed.value ? 60 : 250);
        return Padding(
          padding: EdgeInsets.only(bottom: lift.toDouble()),
          child: _buildFloatingBar(context, controller),
        );
      }),
    );
  }

  /// 顶部工具条：文件排序筛选 + 一键折叠/展开所有主播文件夹
  Widget _buildToolbar(BuildContext context, TsUnpackController controller) {
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
    TsUnpackController controller,
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
    if (value != null) {
      controller.setSortMode(value);
    }
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

  /// 未设置存储路径
  Widget _buildNoPath(BuildContext context) {
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
                Icons.folder_off_outlined,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Text("请先设置音频存储路径", style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              "在设置中配置存储路径后，才能扫描 TS 文件",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.xl),
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

  /// 没有 TS 文件
  Widget _buildEmpty(BuildContext context) {
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
                Icons.unarchive_outlined,
                size: 36,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Text("没有发现 TS 文件", style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              "录制产生的 TS 片段会出现在这里",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 文件列表（按主播名分组）
  Widget _buildFileList(BuildContext context, TsUnpackController controller) {
    var theme = Theme.of(context);
    return Obx(() {
      // 只订阅 groups.length / sortMode, 进度变化不重建列表
      var groups = controller.groups;
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: groups.length,
        // 避免首屏一次性 build 上百个 Row 导致掉帧
        scrollCacheExtent: const ScrollCacheExtent.pixels(600),
        itemBuilder: (context, groupIndex) {
          var group = groups[groupIndex];
          var files = group.files;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 分组表头 ──
              Obx(() {
                var isExpanded = group.isExpanded.value;
                return Material(
                  color: AppSurface.header(theme.colorScheme),
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
                          // 合并碎片按钮（有碎片时显示）
                          Obx(() {
                            var count = controller.getGroupFragmentCount(
                              groupIndex,
                            );
                            if (count == 0) return const SizedBox.shrink();
                            final mergeFg = theme.brightness == Brightness.dark
                                ? Colors.teal.shade300
                                : Colors.teal.shade700;
                            return Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: GestureDetector(
                                onTap: () =>
                                    controller.mergeGroupFragments(groupIndex),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mergeFg.withAlpha(26),
                                    borderRadius: AppRadius.rXs,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.merge,
                                        size: 13,
                                        color: mergeFg,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        "合并($count)",
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          height: 1.25,
                                          color: mergeFg,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: 4),
                          // 全选该主播：三态勾选（全选/部分/未选）
                          Obx(() {
                            var targets = group.files
                                .where((f) => !f.isRecording)
                                .toList();
                            var selCount = targets
                                .where((f) => f.isSelected.value)
                                .length;
                            var allSel =
                                targets.isNotEmpty &&
                                selCount == targets.length;
                            var someSel = selCount > 0 && !allSel;
                            return GestureDetector(
                              // 整块透明区都可点（opaque），触摸区 40px，图标仍 20px
                              behavior: HitTestBehavior.opaque,
                              onTap: targets.isEmpty
                                  ? null
                                  : () => controller.toggleGroupSelection(
                                      groupIndex,
                                    ),
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(
                                  allSel
                                      ? Icons.check_box
                                      : someSel
                                      ? Icons.indeterminate_check_box
                                      : Icons.check_box_outline_blank,
                                  size: 20,
                                  color: allSel
                                      ? Colors.orange
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }),
                          const SizedBox(width: AppSpace.md),
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

              // ── 文件列表 ──
              Obx(() {
                if (!group.isExpanded.value) return const SizedBox.shrink();
                return Column(
                  children: [
                    for (var i = 0; i < files.length; i++)
                      _buildFileRow(
                        context,
                        controller,
                        files[i],
                        i,
                        files.length,
                        groupIndex,
                      ),
                  ],
                );
              }),
            ],
          );
        },
      );
    });
  }

  /// 单个文件行
  Widget _buildFileRow(
    BuildContext context,
    TsUnpackController controller,
    FileItem file,
    int index,
    int total,
    int groupIndex,
  ) {
    var theme = Theme.of(context);

    return Obx(() {
      var isUnpacked = file.isUnpacked.value;
      var isSelected = file.isSelected.value;
      // 录制中的不可选；已解包的也可勾选（用于批量删除），
      // 点解包时 startBatchUnpack 会过滤已解包，不会重复解包
      var canSelect = !file.isRecording;

      // 语义色：录制中橙、中断红、已解包绿
      final accent = file.isRecording
          ? Colors.orange
          : file.isInterrupted && !isUnpacked
          ? Colors.red
          : isUnpacked
          ? Colors.green
          : theme.colorScheme.onSurfaceVariant;

      final rowColor = isSelected
          ? theme.colorScheme.primary.withAlpha(12)
          : file.isRecording
          ? Colors.orange.withAlpha(10)
          : file.isInterrupted && !isUnpacked
          ? Colors.red.withAlpha(7)
          : Colors.transparent;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canSelect ? () => file.isSelected.toggle() : null,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.fromLTRB(13, 7, 16, 7),
          decoration: BoxDecoration(
            color: rowColor,
            border: Border(
              left: BorderSide(
                color: isSelected
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
              // 复选框
              if (canSelect)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (v) => file.isSelected.value = v ?? false,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    semanticLabel: file.fileName,
                    activeColor: theme.colorScheme.primary,
                    checkColor: theme.colorScheme.onPrimary,
                    side: BorderSide(
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
                      width: 1.6,
                    ),
                  ),
                )
              else
                const SizedBox(width: 24),

              const SizedBox(width: 10),

              // 文件名 + 状态
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // 合并序号
                        Obx(() {
                          var mergeIdx = controller.getMergeOrderIndex(file);
                          if (mergeIdx == 0) return const SizedBox.shrink();
                          return Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "$mergeIdx",
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.2,
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: Text(
                            file.fileName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              fontWeight: isUnpacked
                                  ? FontWeight.w400
                                  : FontWeight.w500,
                              color: isUnpacked
                                  ? theme.colorScheme.onSurface.withAlpha(130)
                                  : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            file.fileSize,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 碎片组色点：同组可合并文件同色
                        Obx(() {
                          final gi = controller.fragmentGroupIndexOf(
                            groupIndex,
                            file,
                          );
                          if (gi < 0) return const SizedBox.shrink();
                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color:
                                  kMergeGroupColors[gi %
                                      kMergeGroupColors.length],
                              shape: BoxShape.circle,
                            ),
                          );
                        }),
                        if (file.isInterrupted)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: StatusBadge("中断", tone: StatusTone.danger),
                          ),
                        if (file.isRecording)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: StatusBadge("录制中", tone: StatusTone.warning),
                          ),
                        if (isUnpacked)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: StatusBadge("已解包", tone: StatusTone.success),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // 文件图标
              AppIconTile(
                icon: file.isRecording
                    ? Icons.fiber_manual_record
                    : file.isInterrupted && !isUnpacked
                    ? Icons.warning_amber_rounded
                    : isUnpacked
                    ? Icons.check_circle_outline
                    : Icons.insert_drive_file_outlined,
                size: 28,
                iconSize: 15,
                color: accent,
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 底部悬浮操作栏：5 个动作共享一个 pill 基底
  Widget _buildFloatingBar(
    BuildContext context,
    TsUnpackController controller,
  ) {
    return Obx(() {
      var theme = Theme.of(context);
      // 空状态下 body 已是占位图，不悬浮操作栏
      if (!controller.hasSavePath.value || controller.groups.isEmpty) {
        return const SizedBox.shrink();
      }

      Widget pill(Widget child) {
        return Material(
          elevation: 6,
          shadowColor: theme.colorScheme.shadow.withAlpha(50),
          surfaceTintColor: Colors.transparent,
          color: AppSurface.floating(theme.colorScheme),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: child,
          ),
        );
      }

      if (controller.isProcessing.value) {
        // 处理中进度由全局 GlobalTaskOverlay 统一显示（避免与本地 pill 重叠），
        // 这里收起，空闲态 pill 保持不变
        return const SizedBox.shrink();
      }

      // ── 空闲状态：两态 pill，主动作只留图标 ──
      var selected = controller.selectedCount;
      // 未选中：全选入口 + 合并/删除/解包图标
      if (selected == 0) {
        return pill(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 全选中断
              TextButton(
                onPressed: () => controller.selectInterrupted(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 11,
                  ),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.red,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: const Text("全选中断", style: TextStyle(fontSize: 17)),
              ),
              // 全选已解
              TextButton(
                onPressed: () => controller.selectUnpacked(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 11,
                  ),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: const Text("全选已解", style: TextStyle(fontSize: 17)),
              ),
              Container(
                width: 1,
                height: 34,
                color: theme.dividerColor,
                margin: const EdgeInsets.symmetric(horizontal: 6),
              ),
              // 合并（图标，禁用态）
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.merge, size: 28),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(11),
                tooltip: "合并",
              ),
              // 删除（图标，禁用态）
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.delete_outline, size: 28),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(11),
                tooltip: "删除",
              ),
              // 解包（图标，禁用态）
              FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  visualDensity: VisualDensity.compact,
                  shape: const CircleBorder(),
                ),
                child: const Icon(Icons.unarchive, size: 25),
              ),
            ],
          ),
        );
      }
      // 有选中：计数 + 清空 + 合并 + 删除 + 解包
      return pill(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                "$selected 已选",
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            // 清空选择
            IconButton(
              onPressed: () => controller.deselectAll(),
              icon: const Icon(Icons.close, size: 25),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(11),
              tooltip: "清空选择",
            ),
            Container(
              width: 1,
              height: 34,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
            // 合并（图标，仅同一主播 ≥2 个可点）
            IconButton(
              onPressed: controller.canMergeSelected
                  ? () => controller.mergeSelected()
                  : null,
              icon: const Icon(Icons.merge, size: 28),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(11),
              tooltip: "合并同一主播的 TS 文件",
            ),
            // 删除（图标，选中即可点）
            IconButton(
              onPressed: () => controller.deleteSelected(),
              icon: const Icon(Icons.delete_outline, size: 28),
              color: theme.colorScheme.error,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(11),
              tooltip: "删除",
            ),
            const SizedBox(width: 6),
            // 解包（图标）
            FilledButton(
              onPressed: () => controller.startBatchUnpack(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(17),
                visualDensity: VisualDensity.compact,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.unarchive, size: 28),
            ),
          ],
        ),
      );
    });
  }
}
