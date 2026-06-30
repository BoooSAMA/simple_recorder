import 'dart:io';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/modules/ts_unpack/ts_unpack_service.dart';

class FileItem {
  final String path;
  final String fileName;
  final bool isInterrupted;
  final RxBool isUnpacked;
  final RxBool isSelected;

  FileItem({
    required this.path,
    required this.fileName,
    required this.isInterrupted,
    required bool isUnpacked,
    bool selected = false,
  })  : isUnpacked = RxBool(isUnpacked),
        isSelected = RxBool(selected);

  /// 文件大小（格式化）
  String get fileSize {
    try {
      var file = File(path);
      if (!file.existsSync()) return "文件不存在";
      var bytes = file.lengthSync();
      if (bytes < 1024) return "$bytes B";
      if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) {
      return "未知";
    }
  }
}

class FileGroup {
  final String folderName;
  final List<FileItem> files;
  final RxBool isExpanded;

  FileGroup({
    required this.folderName,
    required this.files,
    bool expanded = true,
  }) : isExpanded = RxBool(expanded);

  int get interruptedCount => files.where((f) => f.isInterrupted).length;
  int get unpackedCount => files.where((f) => f.isUnpacked.value).length;
  int get totalCount => files.length;
}

class TsUnpackController extends GetxController {
  final groups = RxList<FileGroup>();
  final isProcessing = false.obs;
  final progress = 0.0.obs;
  final currentFileIndex = 0.obs;
  final totalFiles = 0.obs;
  final currentFileName = "".obs;
  final hasSavePath = true.obs;

  /// 计算选中的文件总数（不含已解包的）
  int get selectedCount {
    int count = 0;
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isUnpacked.value) count++;
      }
    }
    return count;
  }

  @override
  void onInit() {
    super.onInit();
    scanDirectory();
  }

  /// 扫描音频目录下的所有 TS 文件
  void scanDirectory() {
    var savePath = AppSettingsController.instance.audioSavePath.value;
    if (savePath.isEmpty) {
      hasSavePath.value = false;
      groups.clear();
      return;
    }

    hasSavePath.value = true;
    groups.clear();

    var rootDir = Directory(savePath);
    if (!rootDir.existsSync()) return;

    // 遍历所有子文件夹（按主播名分组）
    var subDirs = rootDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (var subDir in subDirs) {
      var tsFiles = subDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ts'))
          .toList()
        ..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

      if (tsFiles.isEmpty) continue;

      var fileItems = tsFiles.map((f) {
        var name = f.path.split('/').last;
        var isInterrupted = name.contains('_interrupted');
        var isUnpacked = File(f.path.replaceAll('.ts', '.m4a')).existsSync();
        return FileItem(
          path: f.path,
          fileName: name,
          isInterrupted: isInterrupted,
          isUnpacked: isUnpacked,
        );
      }).toList();

      groups.add(FileGroup(
        folderName: subDir.path.split('/').last,
        files: fileItems,
      ));
    }
  }

  /// 全选所有可解包的文件
  void selectAll() {
    for (var group in groups) {
      for (var file in group.files) {
        if (!file.isUnpacked.value) {
          file.isSelected.value = true;
        }
      }
    }
    update();
  }

  /// 仅选中中断文件
  void selectInterrupted() {
    for (var group in groups) {
      for (var file in group.files) {
        file.isSelected.value =
            file.isInterrupted && !file.isUnpacked.value;
      }
    }
    update();
  }

  /// 取消全选
  void deselectAll() {
    for (var group in groups) {
      for (var file in group.files) {
        file.isSelected.value = false;
      }
    }
    update();
  }

  /// 切换分组展开/收起
  void toggleGroup(int index) {
    if (index >= 0 && index < groups.length) {
      groups[index].isExpanded.toggle();
    }
  }

  /// 批量解包所有选中的文件
  Future<void> startBatchUnpack() async {
    var selectedFiles = <FileItem>[];
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isUnpacked.value) {
          selectedFiles.add(file);
        }
      }
    }

    if (selectedFiles.isEmpty) {
      SmartDialog.showToast("请选择需要解包的文件");
      return;
    }

    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = selectedFiles.length;
    currentFileIndex.value = 0;
    currentFileName.value = "";

    var successCount = 0;
    var failCount = 0;
    var failDetails = <String>[];

    for (var i = 0; i < selectedFiles.length; i++) {
      // 检查是否被取消
      if (!isProcessing.value) break;

      var file = selectedFiles[i];
      currentFileIndex.value = i + 1;
      currentFileName.value = file.fileName;

      var result = await TsUnpackService.unpack(
        file.path,
        onProgress: (p) {
          // 单个文件进度占总进度的加权
          var base = i / selectedFiles.length;
          progress.value = base + p / selectedFiles.length;
        },
      );

      if (result.success) {
        successCount++;
        file.isUnpacked.value = true;
        file.isSelected.value = false;
      } else {
        failCount++;
        failDetails.add("${file.fileName}: ${result.error ?? '失败'}");
      }
    }

    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";

    // 汇总结果
    var summary = "解包完成：$successCount 个成功";
    if (failCount > 0) {
      summary += "，$failCount 个失败";
      Log.logPrint("解包失败详情:\n${failDetails.join('\n')}");
    }
    SmartDialog.showToast(summary);
  }

  /// 取消批量解包（处理完当前文件后停止）
  void cancelBatch() {
    isProcessing.value = false;
  }
}
