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
        title: const Text("TS 解包工具"),
        actions: [
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
          return _buildNoPath(context);
        }
        if (controller.groups.isEmpty) {
          return _buildEmpty(context);
        }
        return Column(
          children: [
            Expanded(child: _buildFileList(context, controller)),
            _buildBottomBar(context, controller),
          ],
        );
      }),
    );
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
      padding: const EdgeInsets.only(bottom: 12),
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
      var canSelect = !isUnpacked;

      return InkWell(
        onTap: canSelect
            ? () => file.isSelected.toggle()
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: file.isInterrupted && !isUnpacked
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
                    Text(
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
                file.isInterrupted && !isUnpacked
                    ? Icons.warning_amber_rounded
                    : isUnpacked
                        ? Icons.check_circle_outline
                        : Icons.insert_drive_file_outlined,
                size: 16,
                color: file.isInterrupted && !isUnpacked
                    ? Colors.red
                    : isUnpacked
                        ? Colors.green
                        : theme.colorScheme.onSurface.withAlpha(80),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 底部操作栏
  Widget _buildBottomBar(BuildContext context, TsUnpackController controller) {
    var theme = Theme.of(context);

    return Obx(() {
      if (controller.isProcessing.value) {
        // ── 处理中状态 ──
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: controller.progress.value,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              // 进度文字
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
                      child: const Text("取消", style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }

      // ── 空闲状态 ──
      var selected = controller.selectedCount;
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 全选中断
            TextButton(
              onPressed: () => controller.selectInterrupted(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: Colors.red,
              ),
              child: const Text("全选中断", style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 2),
            // 全选
            TextButton(
              onPressed: () => controller.selectAll(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text("全选", style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 2),
            // 取消选择
            TextButton(
              onPressed: () => controller.deselectAll(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text("取消选择", style: TextStyle(fontSize: 12)),
            ),
            const Spacer(),
            // 开始解包
            FilledButton.icon(
              onPressed: selected > 0 ? () => controller.startBatchUnpack() : null,
              icon: const Icon(Icons.unarchive, size: 16),
              label: Text(
                selected > 0 ? "解包 ($selected)" : "开始解包",
                style: const TextStyle(fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      );
    });
  }
}
