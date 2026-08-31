# third_party — 本地补丁依赖

## ffmpeg_kit_flutter_new_https_gpl (2.1.0)

来源：pub.dev 缓存原样拷贝（FFmpeg 二进制仍从 Maven `com.antonkarpenko:ffmpeg-kit-https-gpl:2.1.0` 拉取，此处只是 Java 插件层）。

**与上游的差异（升级时需重新套用）：**

- `android/src/main/java/com/antonkarpenko/ffmpegkit/FFmpegKitFlutterPlugin.java:111`
  `asyncConcurrencyLimit` 10 → **16**。上游硬编码 10 线程固定池（含无界队列），导致第 11 路录制"假启动"（任务入队不执行）。
  16 与 `RecordingManager.maxConcurrent` 对齐。

通过 `pubspec.yaml` 的 `dependency_overrides` 生效。
