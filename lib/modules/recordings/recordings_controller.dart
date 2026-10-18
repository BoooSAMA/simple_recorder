import 'dart:io';
import 'dart:isolate';

import 'package:ffmpeg_kit_flutter_new_https_gpl/ffprobe_kit.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:simple_recorder/app/app_notify.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/services/global_player_controller.dart';

/// 在后台 isolate 中扫描录音目录（stat/遍历是磁盘 IO，
/// 放主线程会随文件数增长成比例卡顿）。
/// 返回结构: [{folder: String, files: [{path, name, mtimeMs, sizeBytes}]}]，
/// 已完成音频扩展名过滤、分组与组内 mtime 降序排序。
List<Map<String, Object>> _scanSync(String rootPath) {
  final rootDir = Directory(rootPath);
  if (!rootDir.existsSync()) return [];

  final exts = Constant.kAllAudioExtensions;
  final result = <Map<String, Object>>[];

  final subDirs = rootDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (var subDir in subDirs) {
    final entries = <Map<String, Object>>[];
    List<FileSystemEntity> children;
    try {
      children = subDir.listSync();
    } catch (_) {
      // 子目录无权限等原因无法列出 → 跳过该目录，不影响其他分组
      continue;
    }
    for (var f in children) {
      if (f is! File) continue;
      if (!exts.any((ext) => f.path.endsWith(ext))) continue;
      try {
        final stat = f.statSync();
        entries.add({
          'path': f.path,
          'name': f.path.split('/').last,
          'mtimeMs': stat.modified.millisecondsSinceEpoch,
          'sizeBytes': stat.size,
        });
      } catch (_) {
        // 扫描期间文件被删除/无权限 → 跳过该文件
      }
    }
    if (entries.isEmpty) continue;

    entries.sort(
        (a, b) => (b['mtimeMs'] as int).compareTo(a['mtimeMs'] as int));
    result.add({
      'folder': subDir.path.split('/').last,
      'files': entries,
    });
  }
  return result;
}

class RecordingItem {
  final String path;
  final String fileName;
  final String folderName;

  /// 扫描时缓存的元数据（避免 UI/排序时反复 syscall：stat 是磁盘 IO，
  /// 列表每行 build 一次 + 排序 O(n log n) 次调用会明显卡顿）
  final int sizeBytes;
  final int mtimeMs;

  final RxBool isSelected;
  final RxString duration;

  /// 文件名日期键（按文件名日期排序用，构造时只解析一次正则）
  late final String nameDateKey = Constant.parseNameDateKey(fileName);

  RecordingItem({
    required this.path,
    required this.fileName,
    required this.folderName,
    this.sizeBytes = 0,
    this.mtimeMs = 0,
    bool selected = false,
    String duration = "",
  })  : isSelected = RxBool(selected),
        duration = RxString(duration);

  String get fileSize {
    if (sizeBytes < 1024) return "$sizeBytes B";
    if (sizeBytes < 1024 * 1024) {
      return "${(sizeBytes / 1024).toStringAsFixed(1)} KB";
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return "${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String get lastModified {
    final dt = DateTime.fromMillisecondsSinceEpoch(mtimeMs);
    return "${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
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

  /// 文件排序模式: 0=日期降序(最新在前) 1=日期升序(最旧在前) 2=主播名
  final sortMode = 0.obs;

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
    AppNotify.toast(msg);
  }

  Future<void> scanDirectory() async {
    var savePath = AppSettingsController.instance.audioSavePath.value;
    if (savePath.isEmpty) {
      hasSavePath.value = false;
      groups.clear();
      return;
    }

    hasSavePath.value = true;
    isLoading.value = true;
    // 记住各分组折叠状态，重建后恢复（删除后不再自动展开）
    final expandedMap = {
      for (var g in groups) g.folderName: g.isExpanded.value
    };

    // 目录遍历 / stat 全部在后台 isolate 执行，不阻塞主线程
    List<Map<String, Object>> scanned;
    try {
      scanned = await Isolate.run(() => _scanSync(savePath));
    } catch (_) {
      isLoading.value = false;
      return;
    }

    groups.clear();
    for (var g in scanned) {
      final folderName = g['folder'] as String;
      final items = (g['files'] as List).map((e) {
        final m = e as Map;
        return RecordingItem(
          path: m['path'] as String,
          fileName: m['name'] as String,
          folderName: folderName,
          mtimeMs: m['mtimeMs'] as int,
          sizeBytes: m['sizeBytes'] as int,
        );
      }).toList();
      groups.add(RecordGroup(
        folderName: folderName,
        items: items,
        expanded: expandedMap[folderName] ?? true,
      ));
    }

    // 按当前排序模式重排（用户可能已切换过排序方式）
    reSort();

    isLoading.value = false;

    // 当前播放的文件若已不存在（被删除/目录变化）→ 关闭全局播放器
    var playingPath = GlobalPlayerController.instance.currentPath.value;
    if (playingPath.isNotEmpty) {
      var stillExists = groups.any(
          (g) => g.items.any((item) => item.path == playingPath));
      if (!stillExists) {
        GlobalPlayerController.instance.close();
      }
    }

    // 异步探测各文件时长
    _probeDurations();
  }

  /// 跨扫描的时长缓存（path → 已格式化时长），避免重扫后全量重探
  final Map<String, String> _durationCache = {};

  /// 时长探测并发数（FFprobe 也占用 FFmpegKit 线程池，保守限 2）
  static const int _probeConcurrency = 2;

  /// 探测代际：重扫时自增，旧探测循环读取到代际变化后尽快退出
  int _probeGen = 0;

  /// 批量异步探测音频文件时长（限并发 + 可被重扫打断 + 跨扫描缓存）
  Future<void> _probeDurations() async {
    final gen = ++_probeGen;
    final pending = <RecordingItem>[];
    final livePaths = <String>{};
    for (var group in groups) {
      for (var item in group.items) {
        livePaths.add(item.path);
        final cached = _durationCache[item.path];
        if (cached != null && cached.isNotEmpty) {
          item.duration.value = cached;
        } else if (item.duration.value.isEmpty) {
          pending.add(item);
        }
      }
    }
    // 清理已不存在文件的缓存，避免长期运行内存增长
    _durationCache.removeWhere((k, v) => !livePaths.contains(k));

    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (gen != _probeGen) return; // 新一轮扫描已开始，旧循环退出
        if (next >= pending.length) return;
        final item = pending[next++];
        try {
          var session = await FFprobeKit.getMediaInformation(item.path);
          var info = session.getMediaInformation();
          var raw = info?.getDuration();
          if (raw != null && raw.isNotEmpty) {
            var secs = double.tryParse(raw);
            if (secs != null && secs > 0) {
              var min = secs ~/ 60;
              var sec = secs.round() % 60;
              var text =
                  "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
              item.duration.value = text;
              _durationCache[item.path] = text;
            }
          }
        } catch (e) {
          // 单个文件探测失败不影响其他文件
        }
      }
    }

    await Future.wait(List.generate(_probeConcurrency, (_) => worker()));
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

  /// 切换排序模式并按新模式重排文件列表
  void setSortMode(int mode) {
    if (mode == sortMode.value) return;
    sortMode.value = mode;
    reSort();
  }

  /// 按当前排序模式重排所有分组内的文件列表
  /// 0=创建时间降序 1=创建时间升序 2=主播名 3=文件名日期降序 4=文件名日期升序
  /// 全部使用扫描时缓存的元数据，排序过程中零磁盘 IO
  void reSort() {
    for (var group in groups) {
      switch (sortMode.value) {
        case 1: // 创建时间升序（最旧在前，文件 mtime）
          group.items.sort((a, b) => a.mtimeMs.compareTo(b.mtimeMs));
          break;
        case 2: // 主播名
          group.items.sort((a, b) => a.fileName.compareTo(b.fileName));
          break;
        case 3: // 文件名日期降序（新→旧，从文件名解析）
          group.items.sort((a, b) => _compareNameDateKeys(a, b, false));
          break;
        case 4: // 文件名日期升序（旧→新，从文件名解析）
          group.items.sort((a, b) => _compareNameDateKeys(a, b, true));
          break;
        default: // 创建时间降序（最新在前，文件 mtime）
          group.items.sort((a, b) => b.mtimeMs.compareTo(a.mtimeMs));
      }
    }
    groups.refresh();
  }

  /// 按文件名日期键比较（零填充格式可直接字符串比较），解析失败（空键）沉底
  int _compareNameDateKeys(RecordingItem a, RecordingItem b, bool ascending) {
    final ka = a.nameDateKey;
    final kb = b.nameDateKey;
    if (ka.isEmpty && kb.isEmpty) return 0;
    if (ka.isEmpty) return 1;
    if (kb.isEmpty) return -1;
    final c = ka.compareTo(kb);
    return ascending ? c : -c;
  }

  /// 是否有展开的分组（用于折叠按钮图标切换）
  bool get anyExpanded => groups.any((g) => g.isExpanded.value);

  /// 一键收起/展开所有分组：有展开的组则全部收起，否则全部展开
  void toggleCollapseAll() {
    var expand = !anyExpanded;
    for (var group in groups) {
      group.isExpanded.value = expand;
    }
  }
}
