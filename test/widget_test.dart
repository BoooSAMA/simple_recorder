// 主页录制态卡片布局回归测试
//
// 镜像 home_page.dart 中 _RoomCard 录制态的 Column 结构：
//   - Grid tile 尺寸：168x158（360dp 屏宽, crossAxisCount: 2,
//     childAspectRatio: 1.06, grid padding 8, spacing 8）
//   - 卡片内 Padding all(8) → Column 内容预算高度 142
//
// 历史 bug：录制中且 lastError 非空时，独立错误日志块（padding 8 +
// 2 行文本 ≈ 40px）使内容总高 ~191 超出 142 → RenderFlex bottom overflow，
// 黄黑条纹出现在"停止/取消"按钮下方。
// 修复：错误状态合并进"时长·文件大小"行，删除独立错误块 → 高度增量 0。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造录制态卡片（结构与 home_page.dart 对应）。
/// [hasError] 为 true 时模拟 lastError 非空：错误提示显示在时长行内
/// （替换文件大小，复用本行空间，不增加卡片高度）。
Widget buildRecordingCard({required bool hasError}) {
  const errorText = 'FFmpeg 录制中断: 服务器限流, 重连中, 请稍候...';
  return SizedBox(
    width: 168,
    height: 158, // Grid tile 高度 = 168 / 1.06
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像行（56px）
            const SizedBox(
              width: 56,
              height: 56,
              child: ColoredBox(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            // 主播名
            const Text(
              '测试主播',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            // 时长 + 文件大小行（录制态；出错时错误提示替换文件大小）
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fiber_manual_record,
                      size: 10, color: Colors.red),
                  const SizedBox(width: 4),
                  const Text(
                    '00:12',
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
                  const Text(
                    ' · ',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                  if (hasError) ...[
                    const Icon(Icons.error_outline,
                        size: 12, color: Colors.red),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        errorText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                  ] else
                    const Flexible(
                      child: Text(
                        '1.5 MB',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 停止 | 取消 按钮行
            const Row(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: Colors.red,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.stop, size: 16),
                          SizedBox(width: 2),
                          Text('停止',
                              style: TextStyle(fontSize: 12, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: ColoredBox(
                    color: Colors.transparent,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, size: 16),
                          SizedBox(width: 2),
                          Text('取消',
                              style: TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('录制态+错误日志：错误并入时长行后卡片不再溢出 (GREEN)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: Center(child: buildRecordingCard(hasError: true)))),
    );
    expect(tester.takeException(), isNull,
        reason: '错误提示并入时长行后，卡片总高 <= 预算 142，不应溢出');
  });

  testWidgets('录制态正常（无错误）：布局不受影响 (GREEN)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: Center(child: buildRecordingCard(hasError: false)))),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('1.5 MB'), findsOneWidget);
  });
}
