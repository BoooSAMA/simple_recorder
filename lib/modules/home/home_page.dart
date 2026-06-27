import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/modules/home/home_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/recording_manager.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(HomeController());
    return Scaffold(
      appBar: AppBar(
        title: const Text("Simple Recorder"),
        leading: Obx(() {
          if (controller.isLoading.value) {
            final progress = controller.loadProgress.value;
            return Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 2.5,
                    ),
                    if (progress > 0)
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          return IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.checkAllLiveStatus(),
            tooltip: "刷新状态",
          );
        }),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  controller.exportData();
                  break;
                case 'import':
                  controller.importData();
                  break;
                case 'audio_path':
                  Get.toNamed(RoutePath.kAudioSettings);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'audio_path',
                child: ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('音频存储路径'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.upload_file),
                  title: Text('导出关注数据'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_download),
                  title: Text('导入关注数据'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Get.toNamed(RoutePath.kSettings),
            tooltip: "设置",
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Get.toNamed(RoutePath.kSearch),
        child: const Icon(Icons.search),
      ),
      body: Obx(() {
        if (controller.followList.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.radio_outlined, size: 80, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  "还没有收藏的直播间",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Get.toNamed(RoutePath.kSearch),
                  icon: const Icon(Icons.search),
                  label: const Text("搜索直播间"),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            _buildFilterBar(context, controller),
            Expanded(
              child: controller.filterMode.value == 0
                  ? _buildGroupedList(context, controller)
                  : _buildSimpleList(context, controller),
            ),
          ],
        );
      }),
    );
  }

  /// 筛选栏：全部 / 直播中 / 未开播
  Widget _buildFilterBar(BuildContext context, HomeController controller) {
    final liveCount = controller.liveList.length;
    final notLiveCount = controller.notLiveList.length;
    final allCount = controller.followList.length;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _filterChip(context, '直播中', liveCount, 1, controller),
          _filterChip(context, '未开播', notLiveCount, 2, controller),
          _filterChip(context, '全部', allCount, 0, controller),
        ],
      ),
    );
  }

  Widget _filterChip(
      BuildContext context, String label, int count, int mode, HomeController controller) {
    final selected = controller.filterMode.value == mode;
    return Expanded(
      child: InkWell(
        onTap: () => controller.setFilterMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            count > 0 ? '$label $count' : label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withAlpha(180),
            ),
          ),
        ),
      ),
    );
  }

  /// 分组列表：直播中 + 未开播 两个 section（2 列 Grid）
  Widget _buildGroupedList(BuildContext context, HomeController controller) {
    final liveItems = controller.liveList;
    final notLiveItems = controller.notLiveList;

    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.85,
    );

    return RefreshIndicator(
      onRefresh: () => controller.checkAllLiveStatus(),
      child: CustomScrollView(
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(bottom: 4)),
          if (liveItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context, '直播中', liveItems.length,
                icon: Icons.live_tv, color: Colors.green,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RoomCard(
                    key: ValueKey(liveItems[i].id),
                    user: liveItems[i],
                  ),
                  childCount: liveItems.length,
                ),
              ),
            ),
          ],
          if (notLiveItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context, '未开播', notLiveItems.length,
                icon: Icons.schedule, color: Colors.grey,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RoomCard(
                    key: ValueKey(notLiveItems[i].id),
                    user: notLiveItems[i],
                  ),
                  childCount: notLiveItems.length,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, String title, int count, {
    IconData? icon,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color?.withAlpha(30) ?? Colors.grey.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: color ?? Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleList(BuildContext context, HomeController controller) {
    return RefreshIndicator(
      onRefresh: () => controller.checkAllLiveStatus(),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: controller.followList.length,
        itemBuilder: (context, index) {
          var user = controller.followList[index];
          return _RoomCard(
            key: ValueKey(user.id),
            user: user,
          );
        },
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final FollowUser user;

  const _RoomCard({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    var controller = Get.find<HomeController>();
    var liveStatus = user.liveStatus.value;

    var theme = Theme.of(context);
    final isPinned = AppSettingsController.instance.isFollowPinned(user.id);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: isPinned
            ? Border.all(color: Colors.green, width: 2.0)
            : null,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：头像 + 信息（名字在上，状态+pin 在下）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头像
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: user.face.isNotEmpty
                          ? Image.network(user.face, fit: BoxFit.cover)
                          : Center(
                              child: Text(
                                user.userName.isNotEmpty
                                    ? user.userName[0]
                                    : "?",
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 名字 + 状态/pin
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.userName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 开播状态 + pin
                        Row(
                          children: [
                            _StatusIndicator(liveStatus: liveStatus),
                            const Spacer(),
                            IconButton(
                              onPressed: () async {
                                await AppSettingsController.instance
                                    .toggleFollowPin(user.id);
                                controller.filterData();
                              },
                              icon: Icon(
                                isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 16,
                                color: isPinned ? Colors.amber : Colors.grey,
                              ),
                              tooltip: isPinned ? '取消置顶' : '置顶',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 更多菜单
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == "delete") {
                        controller.removeFollow(user);
                      }
                    },
                    icon: const Icon(Icons.more_vert, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: "delete",
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18),
                            SizedBox(width: 8),
                            Text("取消关注"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 录制按钮 — 全宽独立行
              _CompactRecordingControls(
                liveStatus: liveStatus,
                user: user,
                controller: controller,
              ),
              // 录制中的调试日志（响应式）
              _ReactiveDebugLog(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

/// 录制控制按钮（全宽行，含录制时长信息）
class _CompactRecordingControls extends StatelessWidget {
  final int liveStatus;
  final FollowUser user;
  final HomeController controller;

  const _CompactRecordingControls({
    required this.liveStatus,
    required this.user,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final _ = RecordingManager.instance.activeSessions.length;
      var session = RecordingManager.instance.getSession(user.id);
      var isRecording = session?.isRecording.value ?? false;
      var duration = session?.duration.value ?? "00:00";
      var fileSize = session?.fileSize.value ?? "";
      var theme = Theme.of(context);

      if (isRecording) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.fiber_manual_record, size: 10, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  "$duration · $fileSize",
                  style: theme.textTheme.labelSmall?.copyWith(color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => controller.stopRecording(user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stop, color: Colors.white, size: 16),
                          SizedBox(width: 2),
                          Text(
                            "停止",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () => controller.cancelRecording(user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.red, width: 1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, color: Colors.red, size: 16),
                          SizedBox(width: 2),
                          Text(
                            "取消",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }

      final isLive = liveStatus == 2;
      final isUnknown = liveStatus == 0;
      final buttonColor = isLive ? theme.colorScheme.primary : Colors.grey;

      return GestureDetector(
        onTap: () => controller.toggleRecording(user),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: buttonColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLive ? Icons.mic : Icons.mic_none,
                size: 16,
                color: isUnknown ? Colors.grey : buttonColor,
              ),
              const SizedBox(width: 4),
              Text(
                isUnknown ? "检查中" : (isLive ? "录制" : "未开播"),
                style: TextStyle(
                  color: isUnknown ? Colors.grey : buttonColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// 录制中调试日志面板（响应式）
class _ReactiveDebugLog extends StatelessWidget {
  final FollowUser user;

  const _ReactiveDebugLog({required this.user});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 订阅 activeSessions
      // ignore: unused_local_variable
      final _ = RecordingManager.instance.activeSessions.length;
      var session = RecordingManager.instance.getSession(user.id);
      var isRecording = session?.isRecording.value ?? false;
      if (!isRecording) return const SizedBox.shrink();
      var lastError = session?.lastError.value ?? "";
      if (lastError.isEmpty) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          onTap: () => _showDebugLog(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: Colors.red),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    lastError,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

void _showDebugLog(BuildContext context) {
  Get.dialog(
    AlertDialog(
      title: const Text("调试日志"),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: Log.debugLogs.reversed.take(50).map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                "[${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}] ${entry.message}",
                style: TextStyle(
                  fontSize: 11,
                  color: entry.color,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: const Text("关闭"),
        ),
      ],
    ),
  );
}

class _StatusIndicator extends StatelessWidget {
  final int liveStatus;

  const _StatusIndicator({required this.liveStatus});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    switch (liveStatus) {
      case 0:
        color = Colors.grey;
        text = "未知";
      case 1:
        color = Colors.grey;
        text = "未开播";
      case 2:
        color = Colors.green;
        text = "直播中";
      default:
        color = Colors.grey;
        text = "未知";
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
