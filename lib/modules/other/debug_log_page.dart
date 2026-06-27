import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
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
              var msg = Log.debugLogs
                  .map((x) => "${x.time}\r\n${x.message}")
                  .join('\r\n\r\n');
              var dir = await getApplicationDocumentsDirectory();
              var logFile = File(
                  '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.log');
              await logFile.writeAsString(msg);
              SmartDialog.showToast("日志已保存");
            },
            icon: const Icon(Icons.save),
          ),
          IconButton(
            onPressed: () {
              Log.debugLogs.clear();
            },
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
      body: Obx(
        () => ListView.separated(
          itemCount: Log.debugLogs.length,
          separatorBuilder: (_, i) => const Divider(),
          padding: const EdgeInsets.all(12),
          itemBuilder: (_, i) {
            var item = Log.debugLogs[i];
            return SelectableText(
              "${item.time}\r\n${item.message}",
              style: TextStyle(color: item.color, fontSize: 12),
            );
          },
        ),
      ),
    );
  }
}
