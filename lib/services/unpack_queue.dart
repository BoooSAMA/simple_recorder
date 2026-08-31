/// FFmpegKit 插件在 Android 端把所有 FFmpeg 任务（录制 + 解包 + FFprobe）
/// 提交到同一个固定线程池，解包任务与录制争抢线程会拖慢录制启动与清理。
///
/// 此队列把所有解包任务串行化：同一时刻最多一个解包占用线程池，
/// 剩余线程池容量全部留给录制。自动解包入队后立即返回，不阻塞
/// RecordingSession 的清理流程。
class UnpackQueue {
  UnpackQueue._();
  static final UnpackQueue instance = UnpackQueue._();

  Future<void> _tail = Future.value();
  int _pending = 0;

  /// 排队中的任务数（含正在执行的一个）
  int get pendingCount => _pending;

  /// 入队一个解包任务，返回该任务完成后的结果（含排队等待时间）
  Future<T> enqueue<T>(Future<T> Function() task) {
    _pending++;
    final result = _tail.then((_) => task());
    // 串行链不因单个任务失败而断开，但对外原样传递结果/异常
    _tail = result.then<void>((_) {}, onError: (_) {});
    result.whenComplete(() => _pending--);
    return result;
  }
}
