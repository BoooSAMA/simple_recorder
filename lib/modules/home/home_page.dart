import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/modules/home/home_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/services/recording_service.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(HomeController());
    return Scaffold(
      appBar: AppBar(
        title: const Text("Simple Recorder"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.checkAllLiveStatus(),
            tooltip: "刷新状态",
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

        return RefreshIndicator(
          onRefresh: () => controller.checkAllLiveStatus(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: controller.followList.length,
            itemBuilder: (context, index) {
              var user = controller.followList[index];
              return _RoomCard(
                key: ValueKey(user.id),
                user: user,
                controller: controller,
              );
            },
          ),
        );
      }),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final FollowUser user;
  final HomeController controller;

  const _RoomCard({
    super.key,
    required this.user,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    var session = RecordingManager.instance.getSession(user.id);
    var isRecording = session?.isRecording.value ?? false;
    var liveStatus = user.liveStatus.value;
    var sessionDuration = session?.duration.value ?? "00:00";
    var sessionFileSize = session?.fileSize.value ?? "";
    var retryCount = session?.retryCount.value ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (user.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.push_pin,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: user.face.isNotEmpty
                        ? Image.network(user.face, fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              user.userName.isNotEmpty
                                  ? user.userName[0]
                                  : "?",
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.userName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _StatusIndicator(liveStatus: liveStatus),
                          const SizedBox(width: 8),
                          if (isRecording)
                            Text(
                              "$sessionDuration · $sessionFileSize",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (retryCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                "重连中($retryCount/3)",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                    color: isRecording ? Colors.red : (liveStatus == 2 ? Colors.green : Colors.grey),
                    size: 28,
                  ),
                  onPressed: isRecording || liveStatus == 2
                      ? () => controller.toggleRecording(user)
                      : null,
                  tooltip: isRecording ? "停止录制" : "开始录制",
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == "delete") {
                      controller.removeFollow(user);
                    } else if (value == "pin") {
                      controller.pinFollow(user);
                    } else if (value == "unpin") {
                      controller.unpinFollow(user);
                    }
                  },
                  itemBuilder: (_) => [
                    if (user.isPinned)
                      const PopupMenuItem(
                        value: "unpin",
                        child: Row(
                          children: [
                            Icon(Icons.push_pin_outlined, size: 18),
                            SizedBox(width: 8),
                            Text("取消置顶"),
                          ],
                        ),
                      )
                    else
                      const PopupMenuItem(
                        value: "pin",
                        child: Row(
                          children: [
                            Icon(Icons.push_pin, size: 18),
                            SizedBox(width: 8),
                            Text("置顶"),
                          ],
                        ),
                      ),
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
            if (isRecording) _DebugLogPanel(session: session),
          ],
        ),
      ),
    );
  }
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

class _DebugLogPanel extends StatelessWidget {
  final RecordingSession? session;

  const _DebugLogPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
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
}
