import 'dart:async';
import 'dart:collection';

/// FFmpegKit 插件在 Android 端把所有 FFmpeg 任务（录制 + 解包 + FFprobe）
/// 提交到同一个固定线程池，解包任务与录制争抢线程会拖慢录制启动与清理。
///
/// 此队列限制同时执行的解包任务数（默认串行 1，可在设置里开到 3）：
/// 剩余线程池容量留给录制。自动解包入队后立即返回，不阻塞
/// RecordingSession 的清理流程。
class UnpackQueue {
  UnpackQueue._();
  static final UnpackQueue instance = UnpackQueue._();

  /// 同时执行上限（由 UnpackManager 按设置同步，默认 1）
  int maxConcurrent = 1;

  int _running = 0;
  int _pending = 0;
  final Queue<Completer<void>> _waiters = Queue();

  /// 排队中的任务数（含正在执行的）
  int get pendingCount => _pending;

  /// 强制重置：放行所有等待者，后续新任务不再被卡死的旧任务阻塞。
  /// 用于解包/合并卡住时的刷新按钮。旧任务完成时的计数递减已做防负保护。
  /// 注意：只处理等待链，真正跑着的任务由 FFmpegKit.cancel 处理。
  void reset() {
    for (final w in _waiters) {
      if (!w.isCompleted) w.complete();
    }
    _waiters.clear();
    _pending = 0;
  }

  /// 入队一个解包任务，返回该任务完成后的结果（含排队等待时间）
  Future<T> enqueue<T>(Future<T> Function() task) async {
    _pending++;
    // 并发已满则排队等待
    if (_running >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_pending > 0) _pending--;
      // 唤醒下一个排队者
      while (_waiters.isNotEmpty) {
        final next = _waiters.removeFirst();
        if (!next.isCompleted) {
          next.complete();
          break;
        }
      }
    }
  }
}
