import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';

class RecordingItem {
  final String path;
  final String fileName;
  final String folderName;
  final RxBool isSelected;

  RecordingItem({
    required this.path,
    required this.fileName,
    required this.folderName,
    bool selected = false,
  }) : isSelected = RxBool(selected);

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

  int get totalFiles => groups.fold(0, (sum, g) => sum + g.count);
  int get totalFolders => groups.length;

  @override
  void onInit() {
    super.onInit();
    scanDirectory();
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
      var m4aFiles = subDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'))
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

      if (m4aFiles.isEmpty) continue;

      var items = m4aFiles.map((f) {
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
  }

  void toggleGroup(int index) {
    if (index >= 0 && index < groups.length) {
      groups[index].isExpanded.toggle();
    }
  }
}
