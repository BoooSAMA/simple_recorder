# 自定义音频输出格式

**Date:** 2026-07-03
**Status:** Draft
**Version:** 1.0

## Summary

在设置中添加音频输出格式选项，允许用户选择 TS 录制完成后自动解包的目标格式。当前仅支持 M4A（`-c:a copy` 直拷），扩展为支持 MP3、FLAC、WAV、OGG 五种格式，并提供"解包后删除 TS 文件"开关。

## Motivation

用户需求："因为目前是用 ffmpeg 录制的，能不能在设置里加个可以自定义音频格式的功能？"

不同用户对音频格式有不同的需求：
- 默认 M4A/AAC：兼容性好，remux 直拷不损失质量
- MP3：最通用的格式，适合分享给他人
- FLAC：无损存档，适合长期保存
- WAV：音频编辑软件的最佳格式
- OGG 开源格式

## Design

### Architecture

保持现有的"TS 录制 → 自动解包"两阶段架构不变，仅在解包阶段根据用户设置选择输出格式。

```
录制阶段（不变）           解包阶段（根据设置变化）
直播流 ─→ TS 文件 ───────→ M4A / MP3 / FLAC / WAV / OGG
         (-f mpegts,        (根据 audioFormat 选择编码参数)
          -c:a copy)
```

### Data Model

在 `AppSettingsController` 中新增：

```dart
/// 音频输出格式，可选值: m4a, mp3, flac, wav, ogg
final audioFormat = "m4a".obs;

/// 自动解包成功后是否删除源 TS 文件
final deleteTsAfterUnpack = true.obs;
```

持久化 key:
- `audio_format` → 默认 `"m4a"`
- `delete_ts_after_unpack` → 默认 `true`

### Supported Formats

| Format | Extension | FFmpeg Arguments | Type |
|--------|-----------|-----------------|------|
| M4A (default) | `.m4a` | `-c:a copy -vn` | Remux (fastest, lossless) |
| MP3 | `.mp3` | `-c:a libmp3lame -q:a 2 -vn` | Transcode (lossy) |
| FLAC | `.flac` | `-c:a flac -vn` | Transcode (lossless) |
| WAV | `.wav` | `-c:a pcm_s16le -vn` | Transcode (uncompressed) |
| OGG | `.ogg` | `-c:a libvorbis -q:a 4 -vn` | Transcode (lossy) |

### Configuration

```dart
class _AudioFormatConfig {
  final String extension;
  final List<String> arguments;
  final bool needsTranscode;  // true if not -c:a copy
}
```

Static map in `RecordingSession`:

```dart
static const Map<String, _AudioFormatConfig> kAudioFormats = {
  'm4a':  _AudioFormatConfig(ext: '.m4a',  args: ['-c:a', 'copy', '-vn'],           needsTranscode: false),
  'mp3':  _AudioFormatConfig(ext: '.mp3',  args: ['-c:a', 'libmp3lame', '-q:a', '2', '-vn'], needsTranscode: true),
  'flac': _AudioFormatConfig(ext: '.flac', args: ['-c:a', 'flac', '-vn'],            needsTranscode: true),
  'wav':  _AudioFormatConfig(ext: '.wav',  args: ['-c:a', 'pcm_s16le', '-vn'],       needsTranscode: true),
  'ogg':  _AudioFormatConfig(ext: '.ogg',  args: ['-c:a', 'libvorbis', '-q:a', '4', '-vn'], needsTranscode: true),
};
```

## Files Changed

| File | Change |
|------|--------|
| `lib/app/controller/app_settings_controller.dart` | Add `audioFormat` and `deleteTsAfterUnpack` Rx fields + persistence |
| `lib/modules/settings/settings_page.dart` | Add "音频输出格式" menu item + "解包后删除 TS 文件" switch in "录制" section |
| `lib/modules/settings/audio_format_settings_page.dart` | **New file**: format selection page with radio list |
| `lib/services/recording_service.dart` | Rename `_autoUnpackToM4A()` → `_autoUnpackToTargetFormat()`, use config map; conditional TS deletion |
| `lib/modules/ts_unpack/ts_unpack_service.dart` | Add `targetFormat` parameter to `unpack()`, support multi-format output |
| `lib/modules/ts_unpack/ts_unpack_controller.dart` | Pass `audioFormat` from settings to `unpack()` |
| `lib/modules/recordings/recordings_controller.dart` | Widen file filter to include all supported audio extensions |
| `lib/modules/recordings/recordings_page.dart` | Update any hardcoded `.m4a` references |
| `lib/routes/app_pages.dart` | Register new route for format selection page |
| `lib/routes/route_path.dart` | Add route constant for format selection |

## UI Design

### Settings Page Changes

In the "录制" section, after "开播通知":

```
录制
┌─────────────────────────────┐
│ 按主播名自动创建文件夹  [开关] │
│ 开播通知                 [开关] │
├─────────────────────────────┤
│ 音频输出格式     M4A (默认) → │  ← 新增，点击跳转选择页
├─────────────────────────────┤
│ 解包后删除 TS 文件      [开关] │  ← 新增
└─────────────────────────────┘
```

### Audio Format Selection Page

Simple page with a radio list:

```
← 音频输出格式

○ M4A (推荐)  — 直拷复用，最快最无损
○ MP3         — 最通用的音频格式
○ FLAC        — 无损压缩，适合存档
○ WAV         — 未压缩，适合编辑
○ OGG         — 开源格式

当前录制流程：直播流 → TS (中间) → 你的选择
```

Each option shows a radio button + format name + brief description. Selected option persists immediately via controller.

## Edge Cases

1. **已有同名文件**：解包前检查目标路径是否存在同名文件，存在则跳过（当前 M4A 已有此逻辑，扩展到所有格式）
2. **转码失败回退**：如果转码失败，保留 TS 文件并记录错误，不要删除源文件
3. **格式切换对已录制文件的影响**：设置只影响后续录制，不影响已存在的录制文件
4. **手动解包工具**：ts_unpack 页面也跟随全局格式设置，保持一致性
5. **文件浏览器过滤**：不再只显示 .m4a，而是显示所有支持的音频格式文件
6. **OS 兼容性**：所有格式在 Android/iOS/Linux/macOS/Windows 上 FFmpeg 都支持

## Not Doing (YAGNI)

- 不改变录制阶段的 TS 格式（保持断线容错）
- 不支持自定义比特率/质量参数（固定值，后续可扩展）
- 不支持批量转换历史文件
- 不添加格式预设导入/导出
- 不添加实时格式切换（录制中切换需下次录制生效）

## Open Questions

1. 是否需要为 MP3/WAV 等格式提供质量/比特率参数的自定义？
