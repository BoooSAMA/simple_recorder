import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/app/log.dart';
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

      final pinnedIds = AppSettingsController
          .instance.pinnedFollowIds.toList();

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
      int failedCount = 0;
      int skippedCount = 0;

      for (var i = 0; i < followsJson.length; i++) {
        final map = followsJson[i] as Map<String, dynamic>;
        try {
          // bililive 导出的 addTime 格式为 "2026-06-16 00:36:43.380"（空格分隔），
          // DateTime.parse() 需要 ISO 8601 格式（T 分隔），这里做兼容转换
          if (map['addTime'] is String) {
            final t = map['addTime'] as String;
            if (!t.contains('T') && t.contains(' ')) {
              map['addTime'] = t.replaceFirst(' ', 'T');
            }
          }
          final follow = FollowUser.fromJson(map);
          if (!DBService.instance.getFollowExist(follow.id)) {
            await DBService.instance.addFollow(follow);
            importedCount++;
            Log.d('✓ 导入: ${follow.userName}');
          } else {
            skippedCount++;
            Log.d('⊙ 已存在: ${follow.userName}');
          }
        } catch (e) {
          failedCount++;
          Log.e('✗ 失败 #$i: ${map['id']} → $e');
        }
      }

      Log.w('导入统计 → 成功:$importedCount  跳过:$skippedCount  失败:$failedCount');

      EventBus.instance.emit(Constant.kUpdateFollow, null);

      if (pinnedIds.isNotEmpty) {
        for (final id in pinnedIds) {
          AppSettingsController.instance.toggleFollowPin(id);
        }
      }

      SmartDialog.showToast('导入成功，共导入 $importedCount 个关注用户');
    } catch (e) {
      SmartDialog.showToast('导入失败: $e');
    }
  }
}
