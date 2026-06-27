import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
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

  void _showRecordedFiles() {
    var saveDir = controller.audioSavePath.value;
    if (saveDir.isEmpty) {
      SmartDialog.showToast("请先设置音频存储路径");
      return;
    }

    var dir = Directory(saveDir);
    if (!dir.existsSync()) {
      SmartDialog.showToast("存储目录不存在");
      return;
    }

    var files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.m4a'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    if (files.isEmpty) {
      SmartDialog.showToast("暂无录音文件");
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
                  var sizeStr = _formatFileSize(file.lengthSync());
                  var modTime = _formatDateTime(file.lastModifiedSync());
                  return ListTile(
                    leading:
                        const Icon(Icons.audiotrack, color: Colors.grey),
                    title: Text(
                      file.path.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text("$sizeStr · $modTime"),
                    onTap: () => OpenFilex.open(file.path),
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
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
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
    SmartDialog.showToast("音频保存路径已设置");
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
                SmartDialog.showToast("路径不能为空");
                return;
              }
              var dirObj = Directory(dir);
              if (!dirObj.existsSync()) {
                SmartDialog.showToast("目录不存在，请检查路径");
                return;
              }
              Get.back();
              controller.setAudioSavePath(dir);
              SmartDialog.showToast("音频保存路径已设置");
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _openSaveDir() async {
    var saveDir = controller.audioSavePath.value;
    if (saveDir.isEmpty) {
      var appDir = await getApplicationDocumentsDirectory();
      saveDir = appDir.path;
    }
    var dir = Directory(saveDir);
    if (!dir.existsSync()) {
      SmartDialog.showToast("存储目录不存在");
      return;
    }
    try {
      if (Platform.isAndroid) {
        const channel = MethodChannel('com.xycz.simple_live/open_folder');
        await channel.invokeMethod('openFolder', {'path': saveDir});
      } else {
        var result = await OpenFilex.open(saveDir);
        if (result.type != ResultType.done) {
          SmartDialog.showToast("无法打开文件夹，请手动前往路径查看");
        }
      }
    } catch (e) {
      SmartDialog.showToast("无法打开文件夹，请手动前往路径查看");
    }
  }
}
