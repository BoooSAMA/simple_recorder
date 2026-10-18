import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:simple_recorder/app/app_notify.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/widgets/settings/settings_card.dart';

class AudioSettingsPage extends GetView<AppSettingsController> {
  const AudioSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("音频设置")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text("录音", style: Get.textTheme.titleSmall),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text("音频存储路径"),
                    subtitle: Text(
                      controller.audioSavePath.value.isNotEmpty
                          ? controller.audioSavePath.value
                          : "未设置（默认保存至应用文档目录）",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: "手动输入路径",
                          onPressed: _manuallyEditPath,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _selectSavePath,
                          child: Text(
                            controller.audioSavePath.value.isNotEmpty
                                ? "更改"
                                : "选择",
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text("查看录音文件"),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: _showRecordedFiles,
            ),
          ),
          const SizedBox(height: 8),
          SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text("打开存储文件夹"),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: _openSaveDir,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecordedFiles() async {
    var saveDir = controller.audioSavePath.value;
    if (saveDir.isEmpty) {
      AppNotify.toast("请先设置音频存储路径");
      return;
    }

    if (!Directory(saveDir).existsSync()) {
      AppNotify.toast("存储目录不存在");
      return;
    }

    // 目录递归遍历 / stat 在后台 isolate 执行，大目录不卡 UI
    List<Map<String, Object>> files;
    try {
      files = await Isolate.run(() => _scanAudioFilesSync(saveDir));
    } catch (_) {
      files = [];
    }

    if (files.isEmpty) {
      AppNotify.toast("暂无录音文件");
      return;
    }

    Get.bottomSheet(
      Container(
        constraints: BoxConstraints(maxHeight: Get.height * 0.6),
        decoration: BoxDecoration(
          color: Get.theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text("录音文件 (${files.length})",
                      style: Get.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Get.back(), child: const Text("关闭")),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: files.length,
                separatorBuilder: (_, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  var file = files[index];
                  var sizeStr = _formatFileSize(file['sizeBytes'] as int);
                  var modTime = _formatDateTime(
                      DateTime.fromMillisecondsSinceEpoch(
                          file['mtimeMs'] as int));
                  return ListTile(
                    leading:
                        const Icon(Icons.audiotrack, color: Colors.grey),
                    title: Text(
                      file['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text("$sizeStr · $modTime"),
                    onTap: () => OpenFilex.open(file['path'] as String),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _selectSavePath() async {
    String? dir;
    if (Platform.isAndroid) {
      dir = await FilePicker.platform.getDirectoryPath();
    } else {
      dir = await FilePicker.platform.saveFile(
        allowedExtensions: ['mp3'],
        type: FileType.custom,
        fileName: "recording_test.mp3",
      );
      if (dir != null) dir = Directory(dir).parent.path;
    }
    if (dir == null) return;
    controller.setAudioSavePath(dir);
    AppNotify.toast("音频保存路径已设置");
  }

  void _manuallyEditPath() {
    var currentPath = controller.audioSavePath.value;
    var textController = TextEditingController(text: currentPath);
    Get.dialog(
      AlertDialog(
        title: const Text("手动输入路径"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: "输入存储目录的完整路径",
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          maxLines: 3,
          minLines: 1,
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              var dir = textController.text.trim();
              if (dir.isEmpty) {
                AppNotify.toast("路径不能为空");
                return;
              }
              var dirObj = Directory(dir);
              if (!dirObj.existsSync()) {
                AppNotify.toast("目录不存在，请检查路径");
                return;
              }
              Get.back();
              controller.setAudioSavePath(dir);
              AppNotify.toast("音频保存路径已设置");
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _openSaveDir() {
    Get.toNamed(RoutePath.kRecordings);
  }
}

/// 后台 isolate：递归扫描目录下全部音频文件并读取 stat（大小/修改时间），
/// 按修改时间降序排序后返回 [{path, name, mtimeMs, sizeBytes}]。
List<Map<String, Object>> _scanAudioFilesSync(String rootPath) {
  final dir = Directory(rootPath);
  if (!dir.existsSync()) return [];

  final exts = Constant.kAllAudioExtensions;
  final result = <Map<String, Object>>[];
  for (var f in dir.listSync(recursive: true)) {
    if (f is! File) continue;
    if (!exts.any((ext) => f.path.endsWith(ext))) continue;
    try {
      final stat = f.statSync();
      result.add({
        'path': f.path,
        'name': f.path.split('/').last,
        'mtimeMs': stat.modified.millisecondsSinceEpoch,
        'sizeBytes': stat.size,
      });
    } catch (_) {
      // 扫描期间文件被删除/无权限 → 跳过该文件
    }
  }
  result.sort((a, b) => (b['mtimeMs'] as int).compareTo(a['mtimeMs'] as int));
  return result;
}
