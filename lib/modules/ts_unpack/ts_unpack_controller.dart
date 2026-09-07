import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https_gpl/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/modules/ts_unpack/ts_unpack_service.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/services/unpack_queue.dart';

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

  /// 动态判断该文件当前是否正在被录制
  bool get isRecording {
    return RecordingManager.instance.activeSessions.any(
      (s) => s.outputPath == path && s.isRecording.value,
    );
  }

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

  /// 排序模式：0=日期降序（新→旧），1=日期升序（旧→新），2=文件名
  final sortMode = 0.obs;

  /// 计算选中的文件总数（不含已解包和录制中的）
  int get selectedCount {
    int count = 0;
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isUnpacked.value && !file.isRecording) count++;
      }
    }
    return count;
  }

  /// 计算选中中已解包的文件数（可删除）
  int get unpackedSelectedCount {
    int count = 0;
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && file.isUnpacked.value) count++;
      }
    }
    return count;
  }

  /// 检查选中文件是否可合并（同一主播 ≥2 个 TS）
  bool get canMergeSelected {
    String? ownerFolder;
    int count = 0;
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isRecording) {
          if (ownerFolder == null) {
            ownerFolder = group.folderName;
          } else if (ownerFolder != group.folderName) {
            return false; // 跨主播，不可合并
          }
          count++;
        }
      }
    }
    return count >= 2;
  }

  /// 选中文件所属的主播名（仅 canMergeSelected=true 时有效）
  String? get selectedOwnerName {
    for (var group in groups) {
      if (group.files.any((f) => f.isSelected.value)) {
        return group.folderName;
      }
    }
    return null;
  }

  /// 选中文件中需要合并的（录制中的跳过），按修改时间排序
  List<FileItem> get _mergeableSelected {
    var result = <FileItem>[];
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isRecording) {
          result.add(file);
        }
      }
    }
    // 按修改时间排序，确定合并顺序
    result.sort((a, b) {
      var ta = File(a.path).lastModifiedSync();
      var tb = File(b.path).lastModifiedSync();
      return ta.compareTo(tb);
    });
    return result;
  }

  /// 获取文件在合并序列中的序号（从 1 开始），不在序列中返回 0
  int getMergeOrderIndex(FileItem file) {
    if (!canMergeSelected) return 0;
    var mergeable = _mergeableSelected;
    for (var i = 0; i < mergeable.length; i++) {
      if (mergeable[i].path == file.path) return i + 1;
    }
    return 0;
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
        var format = AppSettingsController.instance.audioFormat.value;
        var ext = Constant.audioFormatExtension(format);
        var isUnpacked = File(f.path.replaceAll('.ts', ext)).existsSync();
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

    // 按当前排序模式排组
    _sortGroups();
  }

  /// 按当前排序模式对分组排序
  void _sortGroups() {
    var list = groups.toList();
    switch (sortMode.value) {
      case 0: // 日期降序（最新在前）
        list.sort((a, b) => _latestFileTime(b).compareTo(_latestFileTime(a)));
        break;
      case 1: // 日期升序
        list.sort((a, b) => _latestFileTime(a).compareTo(_latestFileTime(b)));
        break;
      case 2: // 主播名
        list.sort((a, b) => a.folderName.compareTo(b.folderName));
        break;
    }
    groups.assignAll(list);
  }

  /// 取分组中最新文件的修改时间（用于排序）
  DateTime _latestFileTime(FileGroup group) {
    if (group.files.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    var latest = group.files
        .map((f) => File(f.path).lastModifiedSync())
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return latest;
  }

  /// 切换排序模式
  void setSortMode(int mode) {
    sortMode.value = mode;
    _sortGroups();
  }

  /// 全选所有可解包的文件
  void selectAll() {
    for (var group in groups) {
      for (var file in group.files) {
        if (!file.isUnpacked.value && !file.isRecording) {
          file.isSelected.value = true;
        }
      }
    }
    update();
  }

  /// 全选所有已解包的文件（可删除）
  void selectUnpacked() {
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isUnpacked.value) {
          file.isSelected.value = true;
        } else {
          file.isSelected.value = false;
        }
      }
    }
    update();
  }

  /// 删除选中的已解包文件（TS + 对应 M4A）
  Future<void> deleteSelected() async {
    var toDelete = <FileItem>[];
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isRecording) {
          toDelete.add(file);
        }
      }
    }
    if (toDelete.isEmpty) return;

    // 确认对话框
    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("确认删除"),
        content: Text("将删除 ${toDelete.length} 个 TS 文件，是否继续？"),
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
    for (var file in toDelete) {
      try {
        var tsFile = File(file.path);
        if (await tsFile.exists()) await tsFile.delete();
        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    // 重新扫描
    scanDirectory();

    var msg = "已删除 $successCount 个 TS 文件";
    if (failCount > 0) msg += "，$failCount 个失败";
    SmartDialog.showToast(msg);
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

  /// 一键全部展开 / 全部收起
  void toggleCollapseAll() {
    var anyExpanded = groups.any((g) => g.isExpanded.value);
    for (var g in groups) {
      g.isExpanded.value = !anyExpanded;
    }
    update();
  }

  /// 全选/全不选某位主播的可操作文件（录制中的除外）
  void toggleGroupSelection(int index) {
    if (index < 0 || index >= groups.length) return;
    var targets =
        groups[index].files.where((f) => !f.isRecording).toList();
    if (targets.isEmpty) return;
    var allSelected = targets.every((f) => f.isSelected.value);
    for (var f in targets) {
      f.isSelected.value = !allSelected;
    }
    update();
  }

  /// 批量解包所有选中的文件
  Future<void> startBatchUnpack() async {
    var selectedFiles = <FileItem>[];
    for (var group in groups) {
      for (var file in group.files) {
        if (file.isSelected.value && !file.isUnpacked.value && !file.isRecording) {
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

      var targetFormat = AppSettingsController.instance.audioFormat.value;
      // 走全局串行解包队列：与录制中的自动解包共用一条队，
      // 避免与录制争抢 FFmpegKit 插件线程池
      var result = await UnpackQueue.instance.enqueue(
        () => TsUnpackService.unpack(
          file.path,
          targetFormat: targetFormat,
          onProgress: (p) {
            // 单个文件进度占总进度的加权
            var base = i / selectedFiles.length;
            progress.value = base + p / selectedFiles.length;
          },
        ),
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

    // 刷新文件列表（如有 TS 被删除，列表中会消失）
    scanDirectory();
  }

  /// 取消批量解包（处理完当前文件后停止）
  void cancelBatch() {
    isProcessing.value = false;
  }

  /// 检测到的碎片组合数量
  int get fragmentCount {
    var count = 0;
    for (var i = 0; i < groups.length; i++) {
      count += getGroupFragmentCount(i);
    }
    return count;
  }

  /// 检测指定主播的碎片数量
  int getGroupFragmentCount(int groupIndex) {
    if (groupIndex >= groups.length) return 0;
    var group = groups[groupIndex];
    var tsFiles = group.files
        .where((f) => !f.isRecording && !f.isUnpacked.value)
        .toList();
    if (tsFiles.length < 2) return 0;

    var parsed = <_ParsedFile>[];
    for (var f in tsFiles) {
      var info = _parseFileName(f.fileName, f);
      if (info != null) parsed.add(info);
    }
    parsed.sort((a, b) => a.startTime.compareTo(b.startTime));

    var byDate = <String, List<_ParsedFile>>{};
    for (var p in parsed) {
      byDate.putIfAbsent(p.date, () => []).add(p);
    }

    var count = 0;
    for (var entry in byDate.entries) {
      var files = entry.value;
      if (files.length < 2) continue;
      var current = <_ParsedFile>[files.first];
      for (var i = 1; i < files.length; i++) {
        if (_minutesDiff(current.last.endTime, files[i].startTime) <= 5) {
          current.add(files[i]);
        } else {
          if (current.length >= 2) count++;
          current = [files[i]];
        }
      }
      if (current.length >= 2) count++;
    }
    return count;
  }

  /// 合并指定主播的碎片
  Future<void> mergeGroupFragments(int groupIndex) async {
    if (groupIndex >= groups.length) return;
    var group = groups[groupIndex];
    var fragments = _detectFragmentsForGroup(group);
    if (fragments.isEmpty) {
      SmartDialog.showToast("未检测到碎片文件");
      return;
    }

    var totalCount = fragments.fold<int>(0, (s, g) => s + g.files.length);

    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("合并碎片"),
        content: Text(
            "检测到 ${group.folderName} 的 ${fragments.length} 组碎片，共 $totalCount 个文件\n将自动按时间顺序合并"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text("合并"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = totalCount;
    currentFileIndex.value = 0;
    currentFileName.value = "";

    var successCount = 0;
    var failCount = 0;

    for (var frag in fragments) {
      var dir = Directory(frag.files.first.item.path).parent.path;
      var outputPath =
          "$dir/${frag.owner}_${frag.date}_${frag.earliestStart}_${frag.latestEnd}_merged.ts";

      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in frag.files) {
        var escaped = f.item.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();

      currentFileIndex.value++;
      currentFileName.value =
          "${frag.owner} (${frag.files.length} 个片段)";

      // 预先探测各源时长之和，用于 concat 进度换算
      final fragTotal = await _probeTotalSeconds(
          frag.files.map((f) => f.item.path).toList());

      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) {
          var base = (successCount + failCount) / totalCount;
          var weight = frag.files.length / totalCount;
          progress.value = base + p * weight;
        }, totalSeconds: fragTotal),
      );

      if (await listFile.exists()) await listFile.delete();

      if (result) {
        successCount += frag.files.length;
        // 按“合并后删除源 TS 文件”开关决定是否删除源片段
        if (AppSettingsController.instance.deleteTsAfterMerge.value) {
          for (var f in frag.files) {
            try {
              var tsFile = File(f.item.path);
              if (await tsFile.exists()) await tsFile.delete();
            } catch (e) {
              Log.logPrint("删除源文件失败: ${f.item.fileName} - $e");
            }
          }
        }
      } else {
        failCount += frag.files.length;
      }
    }

    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";

    var summary = "碎片合并完成：$successCount 个文件已合并";
    if (failCount > 0) summary += "，$failCount 个失败";
    SmartDialog.showToast(summary);

    scanDirectory();
  }

  /// 检测指定主播的碎片
  List<_FragmentGroup> _detectFragmentsForGroup(dynamic group) {
    var result = <_FragmentGroup>[];
    var tsFiles = group.files
        .where((f) => !f.isRecording && !f.isUnpacked.value)
        .toList();
    if (tsFiles.length < 2) return result;

    var parsed = <_ParsedFile>[];
    for (var f in tsFiles) {
      var info = _parseFileName(f.fileName, f);
      if (info != null) parsed.add(info);
    }
    parsed.sort((a, b) => a.startTime.compareTo(b.startTime));

    var byDate = <String, List<_ParsedFile>>{};
    for (var p in parsed) {
      byDate.putIfAbsent(p.date, () => []).add(p);
    }

    for (var entry in byDate.entries) {
      var files = entry.value;
      if (files.length < 2) continue;
      var groups = <List<_ParsedFile>>[];
      var current = <_ParsedFile>[files.first];
      for (var i = 1; i < files.length; i++) {
        if (_minutesDiff(current.last.endTime, files[i].startTime) <= 5) {
          current.add(files[i]);
        } else {
          if (current.length >= 2) groups.add(current);
          current = [files[i]];
        }
      }
      if (current.length >= 2) groups.add(current);

      for (var g in groups) {
        result.add(_FragmentGroup(
          owner: group.folderName,
          date: entry.key,
          files: g,
          earliestStart: g.first.startTime,
          latestEnd: g.last.endTime,
        ));
      }
    }
    return result;
  }

  /// 一键合并所有检测到的碎片
  Future<void> mergeAllFragments() async {
    // 收集所有碎片
    var allFragments = <_FragmentGroup>[];
    for (var i = 0; i < groups.length; i++) {
      allFragments.addAll(_detectFragmentsForGroup(groups[i]));
    }
    if (allFragments.isEmpty) {
      SmartDialog.showToast("未检测到碎片文件");
      return;
    }

    // 计算总文件数
    var totalCount = allFragments.fold<int>(0, (s, g) => s + g.files.length);

    // 确认对话框
    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("一键合并碎片"),
        content: Text("检测到 ${allFragments.length} 组碎片，共 $totalCount 个文件\n将自动按时间顺序合并"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text("合并"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = totalCount;
    currentFileIndex.value = 0;
    currentFileName.value = "";

    var successCount = 0;
    var failCount = 0;

    for (var group in allFragments) {
      var dir = Directory(group.files.first.item.path).parent.path;
      var outputPath =
          "$dir/${group.owner}_${group.date}_${group.earliestStart}_${group.latestEnd}_merged.ts";

      // 写 concat list
      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in group.files) {
        var escaped = f.item.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();

      currentFileIndex.value++;
      currentFileName.value =
          "${group.owner} (${group.files.length} 个片段)";

      // 预先探测各源时长之和，用于 concat 进度换算
      final groupTotal = await _probeTotalSeconds(
          group.files.map((f) => f.item.path).toList());

      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) {
          // 单组进度
          var base = (successCount + failCount) / totalCount;
          var weight = group.files.length / totalCount;
          progress.value = base + p * weight;
        }, totalSeconds: groupTotal),
      );

      // 删除临时 list
      if (await listFile.exists()) await listFile.delete();

      if (result) {
        // 删除源文件
        successCount += group.files.length;
        if (AppSettingsController.instance.deleteTsAfterMerge.value) {
          for (var f in group.files) {
            try {
              var tsFile = File(f.item.path);
              if (await tsFile.exists()) await tsFile.delete();
            } catch (e) {
              Log.logPrint("删除源文件失败: ${f.item.fileName} - $e");
            }
          }
        }
      } else {
        failCount += group.files.length;
        Log.logPrint("合并失败: ${group.owner} ${group.date}");
      }
    }

    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";

    var summary = "碎片合并完成：$successCount 个文件已合并";
    if (failCount > 0) summary += "，$failCount 个失败";
    SmartDialog.showToast(summary);

    scanDirectory();
  }

  /// 合并选中的同一主播的多个 TS 文件
  Future<void> mergeSelected() async {
    if (!canMergeSelected) {
      SmartDialog.showToast("请选择同一主播的至少 2 个 TS 文件");
      return;
    }

    var files = _mergeableSelected;
    // 按修改时间排序，保证拼出的顺序正确
    files.sort((a, b) {
      var ta = File(a.path).lastModifiedSync();
      var tb = File(b.path).lastModifiedSync();
      return ta.compareTo(tb);
    });

    // 从文件名解析时间范围，用于输出命名
    var owner = selectedOwnerName ?? "unknown";
    var dir = Directory(files.first.path).parent.path;
    var nameParts = _parseTimeRange(files, owner);
    var outputPath = "$dir/${nameParts}_merged.ts";

    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = files.length;
    currentFileIndex.value = 0;
    currentFileName.value = "合并中...";

    try {
      // 写 concat list 文件
      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in files) {
        var escaped = f.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();

      // 调用 FFmpeg concat（预先探测总时长用于进度换算）
      final selTotal =
          await _probeTotalSeconds(files.map((f) => f.path).toList());
      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) {
          progress.value = p;
        }, totalSeconds: selTotal),
      );

      // 删除临时 list 文件
      if (await listFile.exists()) await listFile.delete();

      if (result) {
        // 合并成功，按开关决定是否删除源文件
        if (AppSettingsController.instance.deleteTsAfterMerge.value) {
          for (var f in files) {
            try {
              var tsFile = File(f.path);
              if (await tsFile.exists()) await tsFile.delete();
            } catch (e) {
              Log.logPrint("删除源文件失败: ${f.fileName} - $e");
            }
          }
        }
        SmartDialog.showToast("合并完成 → ${outputPath.split('/').last}");
        scanDirectory();
      } else {
        SmartDialog.showToast("合并失败，请查看日志");
      }
    } catch (e) {
      Log.logPrint("合并异常: $e");
      SmartDialog.showToast("合并异常: $e");
    } finally {
      isProcessing.value = false;
      progress.value = 1.0;
      currentFileName.value = "";
    }
  }

  /// 从文件名解析时间范围，返回形如 `userName_2026-09-05_22-13_22-24` 的字符串
  String _parseTimeRange(List<FileItem> files, String owner) {
    // 文件名格式: {owner}_{date}_{startTime}_{endTime}.ts
    // 例如: userName_2026-09-05_22-13_22-19.ts
    // 也可能是中断文件: userName_2026-09-05_22-13_22-19_interrupted.ts
    var earliestStart = "99-99";
    var latestEnd = "00-00";
    var date = "";

    for (var f in files) {
      var name = f.fileName.replaceAll('.ts', '');
      // 去掉 _interrupted 后缀
      name = name.replaceAll('_interrupted', '');
      // 按 _ 分割: [owner, date, startTime, endTime]
      var parts = name.split('_');
      if (parts.length >= 4) {
        date = parts[1]; // 取日期（所有文件应同一天）
        var start = parts[2];
        var end = parts[3];
        if (start.compareTo(earliestStart) < 0) earliestStart = start;
        if (end.compareTo(latestEnd) > 0) latestEnd = end;
      }
    }

    return "${owner}_${date}_${earliestStart}_$latestEnd";
  }

  /// 执行 FFmpeg concat 协议拼接
  /// FFmpeg concat 拼接（-c copy 直拷）
  ///
  /// [totalSeconds] 为各源文件时长之和（concat 输出总时长），用于把
  /// FFmpeg 日志里的 `time=` 换算成 0.0~1.0 进度；传 0 则无中间进度。
  Future<bool> _runFfmpegConcat(
    String listPath,
    String outputPath,
    void Function(double) onProgress, {
    double totalSeconds = 0,
  }) async {
    final completer = Completer<bool>();

    // 进度统一出口：只允许前进，忽略回退值，避免进度条反复跳动
    var lastProgress = 0.0;
    void emit(double p) {
      p = p.clamp(0.0, 1.0);
      if (p < lastProgress) return;
      lastProgress = p;
      onProgress(p);
    }

    try {
      await FFmpegKit.executeWithArgumentsAsync(
        ['-f', 'concat', '-safe', '0', '-i', listPath, '-c', 'copy', '-y', outputPath],
        (session) async {
          var returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            emit(1.0);
            completer.complete(true);
          } else {
            completer.complete(false);
          }
        },
        (log) {
          if (totalSeconds <= 0) return;
          var msg = log.getMessage();
          // 解析当前位置: "time=01:23:45.67"
          var m = RegExp(r'time=(\d{2}):(\d{2}):(\d{2})\.\d{2}')
              .firstMatch(msg);
          if (m != null) {
            var current = _parseTimeToSeconds(
              m.group(1)!,
              m.group(2)!,
              m.group(3)!,
            );
            emit(current / totalSeconds);
          }
        },
      );
    } catch (e) {
      Log.logPrint("FFmpeg concat 执行失败: $e");
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  /// FFprobe 探测多个文件时长并求和（concat 输出时长 = 各源时长之和）
  Future<double> _probeTotalSeconds(List<String> paths) async {
    var total = 0.0;
    for (var p in paths) {
      try {
        var session = await FFprobeKit.getMediaInformation(p);
        var raw = session.getMediaInformation()?.getDuration();
        var secs = raw != null && raw.isNotEmpty
            ? double.tryParse(raw) ?? 0
            : 0;
        if (secs > 0) total += secs;
      } catch (_) {
        // 单个探测失败不影响其他文件
      }
    }
    return total;
  }

  /// "HH MM SS" → 秒
  int _parseTimeToSeconds(String h, String m, String s) {
    return int.parse(h) * 3600 + int.parse(m) * 60 + int.parse(s);
  }

  /// 解析文件名，返回时间信息
  _ParsedFile? _parseFileName(String fileName, FileItem item) {
    var name = fileName.replaceAll('.ts', '').replaceAll('_interrupted', '');
    var parts = name.split('_');
    // 格式: {owner}_{date}_{startTime}_{endTime}
    if (parts.length < 4) return null;
    var date = parts[1];
    var startTime = parts[2];
    var endTime = parts[3];
    // 验证时间格式 HH-MM
    if (startTime.length != 5 || endTime.length != 5) return null;
    return _ParsedFile(
      date: date,
      startTime: startTime,
      endTime: endTime,
      item: item,
    );
  }

  /// 计算两个 HH-MM 时间字符串之间的分钟差
  int _minutesDiff(String time1, String time2) {
    var t1 = time1.split('-');
    var t2 = time2.split('-');
    if (t1.length != 2 || t2.length != 2) return 9999;
    var m1 = int.tryParse(t1[0])! * 60 + int.tryParse(t1[1])!;
    var m2 = int.tryParse(t2[0])! * 60 + int.tryParse(t2[1])!;
    return (m2 - m1).abs();
  }
}

/// 解析后的文件时间信息
class _ParsedFile {
  final String date;
  final String startTime;
  final String endTime;
  final FileItem item;

  _ParsedFile({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.item,
  });
}

/// 检测到的碎片组合
class _FragmentGroup {
  final String owner;
  final String date;
  final List<_ParsedFile> files;
  final String earliestStart;
  final String latestEnd;

  _FragmentGroup({
    required this.owner,
    required this.date,
    required this.files,
    required this.earliestStart,
    required this.latestEnd,
  });
}
