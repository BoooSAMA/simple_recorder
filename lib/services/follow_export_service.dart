import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';

class FollowExportService {
  static Future<void> exportFollowData() async {
    try {
      final follows = DBService.instance.getFollowList();
      if (follows.isEmpty) {
        SmartDialog.showToast('暂无关注数据可导出');
        return;
      }

      final pinnedIds =
          follows.where((f) => f.isPinned).map((f) => f.id).toList();

      final data = {
        'type': 'simple_recorder_follow',
        'version': 1,
        'exportTime': DateTime.now().toIso8601String(),
        'follows': follows.map((e) => e.toJson()).toList(),
        'pinnedIds': pinnedIds,
      };

      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      final dateStr = DateTime.now().toString().substring(0, 10);

      final inlineSave = Platform.isAndroid || Platform.isIOS;
      final path = await FilePicker.platform.saveFile(
        allowedExtensions: ['json'],
        type: FileType.custom,
        fileName: 'simple_recorder_follow_$dateStr.json',
        bytes: inlineSave ? bytes : null,
      );

      if (path == null) return;

      if (!inlineSave) {
        await File(path).writeAsBytes(bytes);
      }

      SmartDialog.showToast('导出成功');
    } catch (e) {
      SmartDialog.showToast('导出失败: $e');
    }
  }

  static Future<void> importFollowData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowedExtensions: ['json'],
        type: FileType.custom,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) {
        SmartDialog.showToast('无法读取文件');
        return;
      }

      final raw = await File(filePath).readAsString();
      Map<String, dynamic> data;
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        SmartDialog.showToast('文件格式错误，解析失败');
        return;
      }

      if (data['type'] != 'simple_recorder_follow' &&
          data['type'] != 'bililive_follow') {
        SmartDialog.showToast('不支持的文件格式');
        return;
      }

      final followsJson = data['follows'] as List<dynamic>? ?? [];
      final pinnedIds =
          (data['pinnedIds'] as List<dynamic>?)?.cast<String>().toSet() ??
              <String>{};

      final confirm = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('导入关注数据'),
          content: Text('即将导入 ${followsJson.length} 个关注用户，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Get.back(result: true),
              child: const Text('确定'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      int importedCount = 0;
      for (final json in followsJson) {
        try {
          final follow =
              FollowUser.fromJson(json as Map<String, dynamic>);
          if (!DBService.instance.getFollowExist(follow.id)) {
            await DBService.instance.addFollow(follow);
            importedCount++;
          }
        } catch (_) {}
      }

      if (pinnedIds.isNotEmpty) {
        for (final id in pinnedIds) {
          await DBService.instance.pinFollow(id);
        }
      }

      SmartDialog.showToast('导入成功，共导入 $importedCount 个关注用户');
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
    }
  }
}
