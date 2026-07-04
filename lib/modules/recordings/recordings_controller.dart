import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';

class RecordingItem {
  final String path;
  final String fileName;
  final String folderName;
  final RxBool isSelected;
  final RxString duration;

  RecordingItem({
    required this.path,
    required this.fileName,
    required this.folderName,
    bool selected = false,
    String duration = "",
  })  : isSelected = RxBool(selected),
        duration = RxString(duration);

  String get fileSize {
    try {
      var file = File(path);
      if (!file.existsSync()) return "";
      var bytes = file.lengthSync();
      if (bytes < 1024) return "$bytes B";
      if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {
      return "";
    }
  }

  String get lastModified {
    try {
      var dt = File(path).lastModifiedSync();
      return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "";
    }
  }
}

class RecordGroup {
  final String folderName;
  final List<RecordingItem> items;
  final RxBool isExpanded;

  RecordGroup({
    required this.folderName,
    required this.items,
    bool expanded = true,
  }) : isExpanded = RxBool(expanded);

  int get count => items.length;
}

class RecordingsController extends GetxController {
  final groups = RxList<RecordGroup>();
  final hasSavePath = true.obs;
  final isLoading = false.obs;
  final isSelectMode = false.obs;

  int get totalFiles => groups.fold(0, (sum, g) => sum + g.count);
  int get totalFolders => groups.length;

  int get selectedCount {
    int count = 0;
    for (var group in groups) {
      for (var item in group.items) {
        if (item.isSelected.value) count++;
      }
    }
    return count;
  }

  @override
  void onInit() {
    super.onInit();
    scanDirectory();
  }

  void toggleSelectMode() {
    isSelectMode.value = !isSelectMode.value;
    if (!isSelectMode.value) {
      // 退出选择模式 → 清除选中
      for (var group in groups) {
        for (var item in group.items) {
          item.isSelected.value = false;
        }
      }
    }
  }

  void toggleSelection(RecordingItem item) {
    item.isSelected.toggle();
  }

  Future<void> deleteSelected() async {
    var toDelete = <RecordingItem>[];
    for (var group in groups) {
      for (var item in group.items) {
        if (item.isSelected.value) toDelete.add(item);
      }
    }
    if (toDelete.isEmpty) return;

    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("确认删除"),
        content: Text("将删除 ${toDelete.length} 个录音文件，是否继续？"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("删除"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    var successCount = 0;
    var failCount = 0;
    for (var item in toDelete) {
      try {
        if (await File(item.path).exists()) {
          await File(item.path).delete();
        }
        successCount++;
      } catch (_) {
        failCount++;
      }
    }

    scanDirectory();
    isSelectMode.value = false;

    var msg = "已删除 $successCount 个文件";
    if (failCount > 0) msg += "，$failCount 个失败";
    SmartDialog.showToast(msg);
  }

  void scanDirectory() {
    var savePath = AppSettingsController.instance.audioSavePath.value;
    if (savePath.isEmpty) {
      hasSavePath.value = false;
      groups.clear();
      return;
    }

    hasSavePath.value = true;
    isLoading.value = true;
    groups.clear();

    var rootDir = Directory(savePath);
    if (!rootDir.existsSync()) {
      isLoading.value = false;
      return;
    }

    // 按子文件夹分组
    var subDirs = rootDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (var subDir in subDirs) {
      var audioFiles = subDir
          .listSync()
          .whereType<File>()
          .where((f) => Constant.kAllAudioExtensions
              .any((ext) => f.path.endsWith(ext)))
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

      if (audioFiles.isEmpty) continue;

      var items = audioFiles.map((f) {
        var name = f.path.split('/').last;
        return RecordingItem(
          path: f.path,
          fileName: name,
          folderName: subDir.path.split('/').last,
        );
      }).toList();

      groups.add(RecordGroup(
        folderName: subDir.path.split('/').last,
        items: items,
      ));
    }

    isLoading.value = false;

    // 异步探测各文件时长
    _probeDurations();
  }

  /// 批量异步探测音频文件时长
  Future<void> _probeDurations() async {
    for (var group in groups) {
      for (var item in group.items) {
        try {
          var session = await FFprobeKit.getMediaInformation(item.path);
          var info = session.getMediaInformation();
          var raw = info?.getDuration();
          if (raw != null && raw.isNotEmpty) {
            var secs = double.tryParse(raw);
            if (secs != null && secs > 0) {
              var min = secs ~/ 60;
              var sec = secs.round() % 60;
              item.duration.value =
                  "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
            }
          }
        } catch (e) {
          // 单个文件探测失败不影响其他文件
        }
      }
    }
  }

  void toggleGroup(int index) {
    if (index >= 0 && index < groups.length) {
      groups[index].isExpanded.toggle();
    }
  }

  /// 切换分组中所有文件的选择状态
  void toggleGroupSelection(int groupIndex) {
    if (groupIndex >= 0 && groupIndex < groups.length) {
      var group = groups[groupIndex];
      var allSelected = group.items.every((item) => item.isSelected.value);
      for (var item in group.items) {
        item.isSelected.value = !allSelected;
      }
    }
  }
}
