import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffmpeg_kit.dart';
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

/// 解包/合并的常驻后台服务 - 独立于页面生命周期
///
/// 原先逻辑寄生在 TsUnpackPage 的 Controller 里，切页即销毁导致批量任务中断。
/// 本服务 permanent 常驻，页面只做订阅，批量任务在后台完美跑完。
class UnpackManager extends GetxController {
  static UnpackManager get instance => Get.find<UnpackManager>();

  // ── 文件状态 (与 TsUnpackController 复用同一套模型, 避免循环依赖此处重定义) ──
  final groups = RxList<UnpackGroup>();
  final hasSavePath = true.obs;
  final sortMode = 0.obs; // 0=日期降序 1=升序 2=主播名

  // ── 批量进度 (页面悬浮进度条只订阅这几个, 不牵连文件列表) ──
  final isProcessing = false.obs;
  final progress = 0.0.obs;
  final currentFileIndex = 0.obs;
  final totalFiles = 0.obs;
  final currentFileName = "".obs;

  // 进度节流
  Timer? _progressThrottle;
  double _pendingProgress = 0;

  @override
  void onInit() {
    super.onInit();
    scanDirectory();
  }

  // ── 扫描 ──

  Future<void> scanDirectory() async {
    var savePath = AppSettingsController.instance.audioSavePath.value;
    if (savePath.isEmpty) {
      hasSavePath.value = false;
      groups.clear();
      return;
    }
    hasSavePath.value = true;

    var scanned = await Isolate.run(() => _scanSync(savePath));
    // 在主 Isolate 补上动态 isUnpacked/isRecording 的 Rx 包装
    var format = AppSettingsController.instance.audioFormat.value;
    var ext = Constant.audioFormatExtension(format);
    var result = <UnpackGroup>[];
    for (var g in scanned) {
      var items = g.files.map((f) {
        var isUnpacked = File(f.path.replaceAll('.ts', ext)).existsSync();
        return UnpackFileItem(
          path: f.path,
          fileName: f.fileName,
          isInterrupted: f.isInterrupted,
          isUnpacked: isUnpacked,
        );
      }).toList();
      // 组内按修改时间降序(最新在前) - 已在 isolate 内排过, 这里不再重复
      result.add(UnpackGroup(folderName: g.folderName, files: items));
    }
    groups.assignAll(result);
    _sortGroups();
  }

  /// 同步扫描逻辑 - 在后台 Isolate 执行, 禁止触碰 GetX/Rx
  static List<_RawGroup> _scanSync(String savePath) {
    var rootDir = Directory(savePath);
    if (!rootDir.existsSync()) return [];
    var subDirs = rootDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    var out = <_RawGroup>[];
    for (var subDir in subDirs) {
      var tsFiles = subDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ts'))
          .toList()
        ..sort((a, b) {
          // 同步 lastModified, 在 isolate 内批量做比主线程好
          var ta = a.lastModifiedSync();
          var tb = b.lastModifiedSync();
          return tb.compareTo(ta);
        });
      if (tsFiles.isEmpty) continue;
      var raws = tsFiles.map((f) {
        var name = f.path.split('/').last;
        return _RawFile(
          path: f.path,
          fileName: name,
          isInterrupted: name.contains('_interrupted'),
          lastMs: f.lastModifiedSync().millisecondsSinceEpoch,
        );
      }).toList();
      out.add(_RawGroup(folderName: subDir.path.split('/').last, files: raws));
    }
    return out;
  }

  void _sortGroups() {
    var list = groups.toList();
    switch (sortMode.value) {
      case 0:
        list.sort((a, b) => _latestMs(b).compareTo(_latestMs(a)));
        break;
      case 1:
        list.sort((a, b) => _latestMs(a).compareTo(_latestMs(b)));
        break;
      case 2:
        list.sort((a, b) => a.folderName.compareTo(b.folderName));
        break;
    }
    groups.assignAll(list);
  }

  int _latestMs(UnpackGroup g) {
    if (g.files.isEmpty) return 0;
    // files 已按时间降序, 首个即最新; 避免再次 lastModifiedSync
    // 但 isolate 扫描后主线程的 FileItem 没存 lastMs, 这里用文件时间兜底一次
    var maxMs = 0;
    for (var f in g.files) {
      try {
        var ms = File(f.path).lastModifiedSync().millisecondsSinceEpoch;
        if (ms > maxMs) maxMs = ms;
      } catch (_) {}
    }
    return maxMs;
  }

  void setSortMode(int mode) {
    sortMode.value = mode;
    _sortGroups();
  }

  void toggleGroup(int index) {
    if (index >= 0 && index < groups.length) groups[index].isExpanded.toggle();
  }

  void toggleCollapseAll() {
    var anyExpanded = groups.any((g) => g.isExpanded.value);
    for (var g in groups) g.isExpanded.value = !anyExpanded;
  }

  // ── 选择 ──

  int get selectedCount {
    var c = 0;
    for (var g in groups) {
      for (var f in g.files) {
        if (f.isSelected.value && !f.isUnpacked.value && !f.isRecording) c++;
      }
    }
    return c;
  }

  int get unpackedSelectedCount {
    var c = 0;
    for (var g in groups) {
      for (var f in g.files) if (f.isSelected.value && f.isUnpacked.value) c++;
    }
    return c;
  }

  bool get canMergeSelected {
    String? owner;
    var count = 0;
    for (var g in groups) {
      for (var f in g.files) {
        if (f.isSelected.value && !f.isRecording) {
          owner ??= g.folderName;
          if (owner != g.folderName) return false;
          count++;
        }
      }
    }
    return count >= 2;
  }

  String? get selectedOwnerName {
    for (var g in groups) if (g.files.any((f) => f.isSelected.value)) return g.folderName;
    return null;
  }

  List<UnpackFileItem> get _mergeableSelected {
    var r = <UnpackFileItem>[];
    for (var g in groups) for (var f in g.files) if (f.isSelected.value && !f.isRecording) r.add(f);
    r.sort((a, b) {
      var ta = File(a.path).lastModifiedSync();
      var tb = File(b.path).lastModifiedSync();
      return ta.compareTo(tb);
    });
    return r;
  }

  int getMergeOrderIndex(UnpackFileItem file) {
    if (!canMergeSelected) return 0;
    var list = _mergeableSelected;
    for (var i = 0; i < list.length; i++) if (list[i].path == file.path) return i + 1;
    return 0;
  }

  void selectAll() {
    for (var g in groups) for (var f in g.files) if (!f.isUnpacked.value && !f.isRecording) f.isSelected.value = true;
  }

  void selectUnpacked() {
    for (var g in groups) for (var f in g.files) f.isSelected.value = f.isUnpacked.value;
  }

  void selectInterrupted() {
    for (var g in groups) for (var f in g.files) f.isSelected.value = f.isInterrupted && !f.isUnpacked.value;
  }

  void deselectAll() {
    for (var g in groups) for (var f in g.files) f.isSelected.value = false;
  }

  void toggleGroupSelection(int index) {
    if (index < 0 || index >= groups.length) return;
    var targets = groups[index].files.where((f) => !f.isRecording).toList();
    if (targets.isEmpty) return;
    var all = targets.every((f) => f.isSelected.value);
    for (var f in targets) f.isSelected.value = !all;
  }

  Future<void> deleteSelected() async {
    var toDelete = <UnpackFileItem>[];
    for (var g in groups) for (var f in g.files) if (f.isSelected.value && !f.isRecording) toDelete.add(f);
    if (toDelete.isEmpty) return;
    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("确认删除"),
        content: Text("将删除 ${toDelete.length} 个 TS 文件，是否继续？"),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
          TextButton(onPressed: () => Get.back(result: true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text("删除")),
        ],
      ),
    );
    if (confirm != true) return;
    var ok = 0, fail = 0;
    for (var f in toDelete) {
      try {
        var file = File(f.path);
        if (await file.exists()) await file.delete();
        ok++;
      } catch (_) { fail++; }
    }
    await scanDirectory();
    var msg = "已删除 $ok 个 TS 文件";
    if (fail > 0) msg += "，$fail 个失败";
    SmartDialog.showToast(msg);
  }

  // ── 解包/合并 (后台串行, 进度节流) ──

  void _emitProgress(double p) {
    _pendingProgress = p.clamp(0.0, 1.0);
    _progressThrottle ??= Timer(const Duration(milliseconds: 80), () {
      progress.value = _pendingProgress;
      _progressThrottle = null;
    });
  }

  Future<void> startBatchUnpack() async {
    var selectedFiles = <UnpackFileItem>[];
    for (var g in groups) for (var f in g.files) if (f.isSelected.value && !f.isUnpacked.value && !f.isRecording) selectedFiles.add(f);
    if (selectedFiles.isEmpty) {
      SmartDialog.showToast("请选择需要解包的文件");
      return;
    }
    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = selectedFiles.length;
    currentFileIndex.value = 0;
    currentFileName.value = "";
    var successCount = 0, failCount = 0;
    var failDetails = <String>[];
    for (var i = 0; i < selectedFiles.length; i++) {
      if (!isProcessing.value) break;
      var file = selectedFiles[i];
      currentFileIndex.value = i + 1;
      currentFileName.value = file.fileName;
      var targetFormat = AppSettingsController.instance.audioFormat.value;
      var result = await UnpackQueue.instance.enqueue(
        () => TsUnpackService.unpack(file.path, targetFormat: targetFormat, onProgress: (p) {
          _emitProgress(i / selectedFiles.length + p / selectedFiles.length);
        }),
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
    _progressThrottle?.cancel();
    _progressThrottle = null;
    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";
    var summary = "解包完成：$successCount 个成功";
    if (failCount > 0) {
      summary += "，$failCount 个失败";
      Log.logPrint("解包失败详情:\n${failDetails.join('\n')}");
    }
    SmartDialog.showToast(summary);
    await scanDirectory();
  }

  void cancelBatch() => isProcessing.value = false;

  // ── 合并 (复用已有逻辑, 进度同样节流) ──

  int get fragmentCount {
    var c = 0;
    for (var i = 0; i < groups.length; i++) c += getGroupFragmentCount(i);
    return c;
  }

  int getGroupFragmentCount(int groupIndex) {
    if (groupIndex >= groups.length) return 0;
    var group = groups[groupIndex];
    var tsFiles = group.files.where((f) => !f.isRecording && !f.isUnpacked.value).toList();
    if (tsFiles.length < 2) return 0;
    var parsed = <_ParsedFile>[];
    for (var f in tsFiles) {
      var info = _parseFileName(f.fileName, f);
      if (info != null) parsed.add(info);
    }
    parsed.sort((a, b) => a.startTime.compareTo(b.startTime));
    var byDate = <String, List<_ParsedFile>>{};
    for (var p in parsed) byDate.putIfAbsent(p.date, () => []).add(p);
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
        content: Text("检测到 ${group.folderName} 的 ${fragments.length} 组碎片，共 $totalCount 个文件\n将自动按时间顺序合并"),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
          TextButton(onPressed: () => Get.back(result: true), child: const Text("合并")),
        ],
      ),
    );
    if (confirm != true) return;
    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = totalCount;
    currentFileIndex.value = 0;
    currentFileName.value = "";
    var successCount = 0, failCount = 0;
    for (var frag in fragments) {
      var dir = Directory(frag.files.first.item.path).parent.path;
      var outputPath = "$dir/${frag.owner}_${frag.date}_${frag.earliestStart}_${frag.latestEnd}_merged.ts";
      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in frag.files) {
        var escaped = f.item.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();
      currentFileIndex.value++;
      currentFileName.value = "${frag.owner} (${frag.files.length} 个片段)";
      // 零 IO 估算总时长 + 源总大小（concat 直拷，大小比例即进度）
      final fragPaths = frag.files.map((f) => f.item.path).toList();
      final fragTotal = _estimateSecondsFromNames(frag.files.map((f) => f.item.fileName).toList());
      final fragBytes = _sourceTotalBytes(fragPaths);
      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) {
          var base = (successCount + failCount) / totalCount;
          var weight = frag.files.length / totalCount;
          _emitProgress(base + p * weight);
        }, totalSeconds: fragTotal, totalBytes: fragBytes),
      );
      if (await listFile.exists()) await listFile.delete();
      if (result) {
        successCount += frag.files.length;
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
    _progressThrottle?.cancel();
    _progressThrottle = null;
    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";
    var summary = "碎片合并完成：$successCount 个文件已合并";
    if (failCount > 0) summary += "，$failCount 个失败";
    SmartDialog.showToast(summary);
    await scanDirectory();
  }

  List<_FragmentGroup> _detectFragmentsForGroup(UnpackGroup group) {
    var result = <_FragmentGroup>[];
    var tsFiles = group.files.where((f) => !f.isRecording && !f.isUnpacked.value).toList();
    if (tsFiles.length < 2) return result;
    var parsed = <_ParsedFile>[];
    for (var f in tsFiles) {
      var info = _parseFileName(f.fileName, f);
      if (info != null) parsed.add(info);
    }
    parsed.sort((a, b) => a.startTime.compareTo(b.startTime));
    var byDate = <String, List<_ParsedFile>>{};
    for (var p in parsed) byDate.putIfAbsent(p.date, () => []).add(p);
    for (var entry in byDate.entries) {
      var files = entry.value;
      if (files.length < 2) continue;
      var groups2 = <List<_ParsedFile>>[];
      var current = <_ParsedFile>[files.first];
      for (var i = 1; i < files.length; i++) {
        if (_minutesDiff(current.last.endTime, files[i].startTime) <= 5) {
          current.add(files[i]);
        } else {
          if (current.length >= 2) groups2.add(current);
          current = [files[i]];
        }
      }
      if (current.length >= 2) groups2.add(current);
      for (var g in groups2) {
        result.add(_FragmentGroup(owner: group.folderName, date: entry.key, files: g, earliestStart: g.first.startTime, latestEnd: g.last.endTime));
      }
    }
    return result;
  }

  Future<void> mergeAllFragments() async {
    var allFragments = <_FragmentGroup>[];
    for (var i = 0; i < groups.length; i++) allFragments.addAll(_detectFragmentsForGroup(groups[i]));
    if (allFragments.isEmpty) {
      SmartDialog.showToast("未检测到碎片文件");
      return;
    }
    var totalCount = allFragments.fold<int>(0, (s, g) => s + g.files.length);
    var confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("一键合并碎片"),
        content: Text("检测到 ${allFragments.length} 组碎片，共 $totalCount 个文件\n将自动按时间顺序合并"),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text("取消")),
          TextButton(onPressed: () => Get.back(result: true), child: const Text("合并")),
        ],
      ),
    );
    if (confirm != true) return;
    isProcessing.value = true;
    progress.value = 0.0;
    totalFiles.value = totalCount;
    currentFileIndex.value = 0;
    currentFileName.value = "";
    var successCount = 0, failCount = 0;
    for (var group in allFragments) {
      var dir = Directory(group.files.first.item.path).parent.path;
      var outputPath = "$dir/${group.owner}_${group.date}_${group.earliestStart}_${group.latestEnd}_merged.ts";
      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in group.files) {
        var escaped = f.item.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();
      currentFileIndex.value++;
      currentFileName.value = "${group.owner} (${group.files.length} 个片段)";
      // 零 IO 估算总时长 + 源总大小
      final groupPaths = group.files.map((f) => f.item.path).toList();
      final groupTotal = _estimateSecondsFromNames(group.files.map((f) => f.item.fileName).toList());
      final groupBytes = _sourceTotalBytes(groupPaths);
      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) {
          var base = (successCount + failCount) / totalCount;
          var weight = group.files.length / totalCount;
          _emitProgress(base + p * weight);
        }, totalSeconds: groupTotal, totalBytes: groupBytes),
      );
      if (await listFile.exists()) await listFile.delete();
      if (result) {
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
    _progressThrottle?.cancel();
    _progressThrottle = null;
    isProcessing.value = false;
    progress.value = 1.0;
    currentFileName.value = "";
    var summary = "碎片合并完成：$successCount 个文件已合并";
    if (failCount > 0) summary += "，$failCount 个失败";
    SmartDialog.showToast(summary);
    await scanDirectory();
  }

  Future<void> mergeSelected() async {
    if (!canMergeSelected) {
      SmartDialog.showToast("请选择同一主播的至少 2 个 TS 文件");
      return;
    }
    var files = _mergeableSelected;
    files.sort((a, b) {
      var ta = File(a.path).lastModifiedSync();
      var tb = File(b.path).lastModifiedSync();
      return ta.compareTo(tb);
    });
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
      var listFile = File("$dir/_concat_list.txt");
      var sink = listFile.openWrite(mode: FileMode.write);
      for (var f in files) {
        var escaped = f.path.replaceAll("'", "'\\''");
        sink.writeln("file '$escaped'");
      }
      await sink.flush();
      await sink.close();
      // 零 IO 估算总时长 + 源总大小
      final selPaths = files.map((f) => f.path).toList();
      final selTotal = _estimateSecondsFromNames(files.map((f) => f.fileName).toList());
      final selBytes = _sourceTotalBytes(selPaths);
      // 大文件预告：超过 500MB 提醒用户需要较长时间
      if (selBytes > 500 * 1024 * 1024) {
        SmartDialog.showToast("文件较大(${(selBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB)，合并需要一些时间");
      }
      var result = await UnpackQueue.instance.enqueue(
        () => _runFfmpegConcat(listFile.path, outputPath, (p) => _emitProgress(p), totalSeconds: selTotal, totalBytes: selBytes),
      );
      if (await listFile.exists()) await listFile.delete();
      if (result) {
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
        await scanDirectory();
      } else {
        SmartDialog.showToast("合并失败，请查看日志");
      }
    } catch (e) {
      Log.logPrint("合并异常: $e");
      SmartDialog.showToast("合并异常: $e");
    } finally {
      _progressThrottle?.cancel();
      _progressThrottle = null;
      isProcessing.value = false;
      progress.value = 1.0;
      currentFileName.value = "";
    }
  }

  String _parseTimeRange(List<UnpackFileItem> files, String owner) {
    var earliestStart = "99-99";
    var latestEnd = "00-00";
    var date = "";
    for (var f in files) {
      var name = f.fileName.replaceAll('.ts', '').replaceAll('_interrupted', '');
      var parts = name.split('_');
      if (parts.length >= 4) {
        date = parts[1];
        var start = parts[2];
        var end = parts[3];
        if (start.compareTo(earliestStart) < 0) earliestStart = start;
        if (end.compareTo(latestEnd) > 0) latestEnd = end;
      }
    }
    return "${owner}_${date}_${earliestStart}_$latestEnd";
  }

  /// FFmpeg concat 拼接（-c copy 直拷）
  ///
  /// 进度双源（取较快者，emit 单调钳制）：
  /// 1. 输出文件大小 / 源总大小 —— 直拷输出≈输入之和，这是最准最实时的；
  /// 2. FFmpeg 日志 `time=` / 总时长 —— 兜底。
  /// 总时长从文件名时间戳估算（零 IO），大文件不再 FFprobe 预探测。
  Future<bool> _runFfmpegConcat(String listPath, String outputPath, void Function(double) onProgress, {double totalSeconds = 0, int totalBytes = 0}) async {
    final completer = Completer<bool>();
    var lastProgress = 0.0;
    void emit(double p) {
      p = p.clamp(0.0, 1.0);
      if (p < lastProgress) return;
      lastProgress = p;
      onProgress(p);
    }
    // 大小进度监测：200ms 刷一次输出文件大小
    Timer? sizeTimer;
    if (totalBytes > 0) {
      sizeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (completer.isCompleted) return;
        try {
          var out = File(outputPath);
          if (out.existsSync()) emit(out.lengthSync() / totalBytes);
        } catch (_) {}
      });
    }
    try {
      await FFmpegKit.executeWithArgumentsAsync(
        ['-f', 'concat', '-safe', '0', '-i', listPath, '-c', 'copy', '-y', outputPath],
        (session) async {
          sizeTimer?.cancel();
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
          var m = RegExp(r'time=(\d{2}):(\d{2}):(\d{2})\.\d{2}').firstMatch(msg);
          if (m != null) {
            var current = _parseTimeToSeconds(m.group(1)!, m.group(2)!, m.group(3)!);
            emit(current / totalSeconds);
          }
        },
      );
    } catch (e) {
      Log.logPrint("FFmpeg concat 执行失败: $e");
      if (!completer.isCompleted) completer.complete(false);
    } finally {
      sizeTimer?.cancel();
    }
    return completer.future;
  }

  /// 源文件总大小（lengthSync 求和，毫秒级，比 FFprobe 探测快得多）
  int _sourceTotalBytes(List<String> paths) {
    var total = 0;
    for (var p in paths) {
      try {
        total += File(p).lengthSync();
      } catch (_) {}
    }
    return total;
  }

  /// 从文件名时间戳估算总时长（秒）：最早开始 ~ 最晚结束，零 IO
  /// 文件名格式 {owner}_{date}_{startTime}_{endTime}，时间 HH-MM
  double _estimateSecondsFromNames(List<String> fileNames) {
    DateTime? earliest;
    DateTime? latest;
    for (var raw in fileNames) {
      var name = raw.replaceAll('.ts', '').replaceAll('_interrupted', '').replaceAll('_merged', '');
      var parts = name.split('_');
      if (parts.length < 4) continue;
      try {
        var dateParts = parts[1].split('-');
        var sParts = parts[2].split('-');
        var eParts = parts[3].split('-');
        if (dateParts.length != 3 || sParts.length != 2 || eParts.length != 2) continue;
        var start = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]), int.parse(sParts[0]), int.parse(sParts[1]));
        var end = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]), int.parse(eParts[0]), int.parse(eParts[1]));
        if (end.isBefore(start)) end = end.add(const Duration(days: 1)); // 跨天
        if (earliest == null || start.isBefore(earliest)) earliest = start;
        if (latest == null || end.isAfter(latest)) latest = end;
      } catch (_) {}
    }
    if (earliest == null || latest == null) return 0;
    return latest.difference(earliest).inSeconds.toDouble();
  }

  int _parseTimeToSeconds(String h, String m, String s) => int.parse(h) * 3600 + int.parse(m) * 60 + int.parse(s);

  _ParsedFile? _parseFileName(String fileName, UnpackFileItem item) {
    var name = fileName.replaceAll('.ts', '').replaceAll('_interrupted', '');
    var parts = name.split('_');
    if (parts.length < 4) return null;
    var date = parts[1];
    var startTime = parts[2];
    var endTime = parts[3];
    if (startTime.length != 5 || endTime.length != 5) return null;
    return _ParsedFile(date: date, startTime: startTime, endTime: endTime, item: item);
  }

  int _minutesDiff(String time1, String time2) {
    var t1 = time1.split('-');
    var t2 = time2.split('-');
    if (t1.length != 2 || t2.length != 2) return 9999;
    var m1 = int.tryParse(t1[0])! * 60 + int.tryParse(t1[1])!;
    var m2 = int.tryParse(t2[0])! * 60 + int.tryParse(t2[1])!;
    return (m2 - m1).abs();
  }
}

// ── 模型 ──

class UnpackFileItem {
  final String path;
  final String fileName;
  final bool isInterrupted;
  final RxBool isUnpacked;
  final RxBool isSelected;
  UnpackFileItem({required this.path, required this.fileName, required this.isInterrupted, required bool isUnpacked, bool selected = false})
      : isUnpacked = RxBool(isUnpacked), isSelected = RxBool(selected);
  bool get isRecording => RecordingManager.instance.activeSessions.any((s) => s.outputPath == path && s.isRecording.value);
  String get fileSize {
    try {
      var file = File(path);
      if (!file.existsSync()) return "文件不存在";
      var bytes = file.lengthSync();
      if (bytes < 1024) return "$bytes B";
      if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    } catch (_) { return "未知"; }
  }
}

class UnpackGroup {
  final String folderName;
  final List<UnpackFileItem> files;
  final RxBool isExpanded;
  UnpackGroup({required this.folderName, required this.files, bool expanded = true}) : isExpanded = RxBool(expanded);
  int get interruptedCount => files.where((f) => f.isInterrupted).length;
  int get unpackedCount => files.where((f) => f.isUnpacked.value).length;
  int get totalCount => files.length;
}

class _RawFile {
  final String path;
  final String fileName;
  final bool isInterrupted;
  final int lastMs;
  _RawFile({required this.path, required this.fileName, required this.isInterrupted, required this.lastMs});
}

class _RawGroup {
  final String folderName;
  final List<_RawFile> files;
  _RawGroup({required this.folderName, required this.files});
}

class _ParsedFile {
  final String date;
  final String startTime;
  final String endTime;
  final UnpackFileItem item;
  _ParsedFile({required this.date, required this.startTime, required this.endTime, required this.item});
}

class _FragmentGroup {
  final String owner;
  final String date;
  final List<_ParsedFile> files;
  final String earliestStart;
  final String latestEnd;
  _FragmentGroup({required this.owner, required this.date, required this.files, required this.earliestStart, required this.latestEnd});
}
