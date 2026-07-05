import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_recorder/app/log.dart';

class DebugLogPage extends StatelessWidget {
  const DebugLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Log"),
        actions: [
          IconButton(
            onPressed: () async {
              try {
                var msg = Log.debugLogs
                    .map((x) => "${x.time}\r\n${x.message}")
                    .join('\r\n\r\n');
                var dir = await getApplicationDocumentsDirectory();
                var filePath =
                    '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.log';
                var logFile = File(filePath);
                await logFile.writeAsString(msg);
                if (context.mounted) {
                  Get.dialog(
                    AlertDialog(
                      title: const Text("保存成功"),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("日志文件已保存到："),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: SelectableText(
                              filePath,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: const Text("确定"),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Get.dialog(
                    AlertDialog(
                      title: const Text("保存失败"),
                      content: Text("$e"),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: const Text("确定"),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.save),
          ),
          IconButton(
            onPressed: () {
              Log.clearDebugLogs();
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: Obx(
        () {
          Log.logCounter.value; // 订阅日志变更
          return ListView.separated(
            itemCount: Log.debugLogs.length,
            separatorBuilder: (_, i) => const Divider(),
            padding: const EdgeInsets.all(12),
            itemBuilder: (_, i) {
              var item = Log.debugLogs[Log.debugLogs.length - 1 - i];
              return SelectableText(
                "${item.time}\r\n${item.message}",
                style: TextStyle(color: item.color, fontSize: 12),
              );
            },
          );
        },
      ),
    );
  }
}
