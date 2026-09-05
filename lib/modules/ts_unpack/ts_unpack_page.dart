import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/modules/ts_unpack/ts_unpack_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';

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
      floatingActionButton: _buildFloatingBar(context, controller),
    );
  }

  /// 顶部工具条：文件排序筛选 + 一键折叠/展开所有主播文件夹
  Widget _buildToolbar(BuildContext context, TsUnpackController controller) {
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
  Future<void> _showSortMenu(BuildContext context,
      TsUnpackController controller, Offset position) async {
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
    if (value != null) {
      controller.setSortMode(value);
    }
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

  /// 未设置存储路径
  Widget _buildNoPath(BuildContext context) {
    var theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              "请先设置音频存储路径",
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "在设置中配置存储路径后，才能扫描 TS 文件",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
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

  /// 没有 TS 文件
  Widget _buildEmpty(BuildContext context) {
    var theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.unarchive_outlined,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            "没有发现 TS 文件",
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 文件列表（按主播名分组）
  Widget _buildFileList(BuildContext context, TsUnpackController controller) {
    var theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: controller.groups.length,
      itemBuilder: (context, groupIndex) {
        var group = controller.groups[groupIndex];
        var files = group.files;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 分组表头 ──
            Obx(() {
              var isExpanded = group.isExpanded.value;
              var hasInterrupted = group.interruptedCount > 0;
              var recordingCount =
                  group.files.where((f) => f.isRecording).length;
              return InkWell(
                onTap: () => controller.toggleGroup(groupIndex),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(60),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          group.folderName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${group.totalCount}个文件",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(150),
                        ),
                      ),
                      if (hasInterrupted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "⚠ ${group.interruptedCount}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (recordingCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "● $recordingCount",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (group.unpackedCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "✅ ${group.unpackedCount}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      // 全选该主播：三态勾选（全选/部分/未选）
                      Obx(() {
                        var targets = group.files
                            .where((f) => !f.isRecording)
                            .toList();
                        var selCount = targets
                            .where((f) => f.isSelected.value)
                            .length;
                        var allSel = targets.isNotEmpty &&
                            selCount == targets.length;
                        var someSel =
                            selCount > 0 && !allSel;
                        return GestureDetector(
                          onTap: targets.isEmpty
                              ? null
                              : () => controller
                                  .toggleGroupSelection(groupIndex),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(
                              allSel
                                  ? Icons.check_box
                                  : someSel
                                      ? Icons.indeterminate_check_box
                                      : Icons.check_box_outline_blank,
                              size: 20,
                              color: allSel
                                  ? Colors.orange
                                  : theme.colorScheme.onSurface
                                      .withAlpha(100),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(width: 12),
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

            // ── 文件列表 ──
            Obx(() {
              if (!group.isExpanded.value) return const SizedBox.shrink();
              return Column(
                children: [
                  for (var i = 0; i < files.length; i++)
                    _buildFileRow(context, controller, files[i], i, files.length),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  /// 单个文件行
  Widget _buildFileRow(
    BuildContext context,
    TsUnpackController controller,
    FileItem file,
    int index,
    int total,
  ) {
    var theme = Theme.of(context);

    return Obx(() {
      var isUnpacked = file.isUnpacked.value;
      var isSelected = file.isSelected.value;
      var canSelect = !isUnpacked && !file.isRecording;

      return InkWell(
        onTap: canSelect
            ? () => file.isSelected.toggle()
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: file.isRecording
                ? Colors.orange.withAlpha(12)
                : file.isInterrupted && !isUnpacked
                    ? Colors.red.withAlpha(8)
                    : null,
            border: index < total - 1
                ? Border(
                    bottom: BorderSide(
                      color: theme.dividerColor,
                      width: 0.3,
                    ),
                  )
                : null,
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
                    activeColor: Colors.orange,
                    checkColor: Colors.white,
                  ),
                )
              else
                const SizedBox(width: 24),

              const SizedBox(width: 8),

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
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "$mergeIdx",
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: Text(
                            file.fileName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: isUnpacked ? FontWeight.normal : FontWeight.w500,
                              color: isUnpacked
                                  ? theme.colorScheme.onSurface.withAlpha(120)
                                  : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          file.fileSize,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withAlpha(100),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (file.isInterrupted)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.red.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "中断",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (file.isRecording)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "录制中",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        if (isUnpacked)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 0),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "已解包",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 文件图标
              Icon(
                file.isRecording
                    ? Icons.fiber_manual_record
                    : file.isInterrupted && !isUnpacked
                        ? Icons.warning_amber_rounded
                        : isUnpacked
                            ? Icons.check_circle_outline
                            : Icons.insert_drive_file_outlined,
                size: 16,
                color: file.isRecording
                    ? Colors.orange
                    : file.isInterrupted && !isUnpacked
                        ? Colors.red
                        : isUnpacked
                            ? (isSelected ? Colors.orange : Colors.green)
                            : theme.colorScheme.onSurface.withAlpha(80),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 底部悬浮操作栏：5 个动作共享一个 pill 基底
  Widget _buildFloatingBar(
      BuildContext context, TsUnpackController controller) {
    return Obx(() {
      var theme = Theme.of(context);
      // 空状态下 body 已是占位图，不悬浮操作栏
      if (!controller.hasSavePath.value || controller.groups.isEmpty) {
        return const SizedBox.shrink();
      }

      Widget pill(Widget child) {
        return Material(
          elevation: 6,
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: child,
          ),
        );
      }

      if (controller.isProcessing.value) {
        // ── 处理中状态 ──
        return Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 32,
          ),
          child: pill(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条 + 百分比
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: controller.progress.value,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 42,
                      child: Text(
                        "${(controller.progress.value * 100).toStringAsFixed(0)}%",
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 进度文字 + 取消
                Row(
                  children: [
                    Text(
                      "${controller.currentFileIndex.value}/${controller.totalFiles.value}",
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.currentFileName.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(150),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: OutlinedButton(
                        onPressed: () => controller.cancelBatch(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        child:
                            const Text("取消", style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }

      // ── 空闲状态：两态 pill，主动作只留图标 ──
      var selected = controller.selectedCount;
      // 未选中：只给全选入口 + 禁用态合并/解包图标
      if (selected == 0) {
        return pill(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 全选中断
              TextButton(
                onPressed: () => controller.selectInterrupted(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.red,
                ),
                child:
                    const Text("全选中断", style: TextStyle(fontSize: 12)),
              ),
              // 全选已解
              TextButton(
                onPressed: () => controller.selectUnpacked(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
                child:
                    const Text("全选已解", style: TextStyle(fontSize: 12)),
              ),
              Container(
                width: 1,
                height: 24,
                color: theme.dividerColor,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
              // 合并（图标，禁用态）
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.merge, size: 20),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
                tooltip: "合并",
              ),
              // 删除（图标，禁用态）
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.delete_outline, size: 20),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(8),
                tooltip: "删除",
              ),
              // 解包（图标，禁用态）
              FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(10),
                  visualDensity: VisualDensity.compact,
                  shape: const CircleBorder(),
                ),
                child: const Icon(Icons.unarchive, size: 18),
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
                ),
              ),
            ),
            // 清空选择
            IconButton(
              onPressed: () => controller.deselectAll(),
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
              tooltip: "清空选择",
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // 合并（图标，仅同一主播 ≥2 个可点）
            IconButton(
              onPressed: controller.canMergeSelected
                  ? () => controller.mergeSelected()
                  : null,
              icon: const Icon(Icons.merge, size: 20),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
              tooltip: "合并同一主播的 TS 文件",
            ),
            // 删除（图标，选中即可点）
            IconButton(
              onPressed: () => controller.deleteSelected(),
              icon: const Icon(Icons.delete_outline, size: 20),
              color: theme.colorScheme.error,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
              tooltip: "删除",
            ),
            const SizedBox(width: 4),
            // 解包（图标）
            FilledButton(
              onPressed: () => controller.startBatchUnpack(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(12),
                visualDensity: VisualDensity.compact,
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.unarchive, size: 20),
            ),
          ],
        ),
      );
    });
  }
}
