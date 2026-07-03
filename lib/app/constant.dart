class Constant {
  static const String kBiliBili = "bilibili";
  static const String kDouYin = "douyin";
  static const String kDouYu = "douyu";
  static const String kHuYa = "huya";
  static const String kMaoerfm = "maoerfm";

  static const String kUpdateFollow = "update_follow";
  static const String kUpdateRecording = "update_recording";
  static const String kPinnedFollowChanged = "pinned_follow_changed";

  // ── 音频格式定义 ──
  static const String kAudioFormatM4A = "m4a";
  static const String kAudioFormatMP3 = "mp3";
  static const String kAudioFormatFLAC = "flac";
  static const String kAudioFormatWAV = "wav";
  static const String kAudioFormatOGG = "ogg";

  /// 所有支持的音频格式列表
  static const List<String> kSupportedAudioFormats = [
    kAudioFormatM4A,
    kAudioFormatMP3,
    kAudioFormatFLAC,
    kAudioFormatWAV,
    kAudioFormatOGG,
  ];

  /// 获取格式对应的文件扩展名（含点号）
  static String audioFormatExtension(String format) {
    switch (format) {
      case kAudioFormatM4A:
        return '.m4a';
      case kAudioFormatMP3:
        return '.mp3';
      case kAudioFormatFLAC:
        return '.flac';
      case kAudioFormatWAV:
        return '.wav';
      case kAudioFormatOGG:
        return '.ogg';
      default:
        return '.m4a';
    }
  }

  /// 获取格式显示名称
  static String audioFormatDisplayName(String format) {
    switch (format) {
      case kAudioFormatM4A:
        return 'M4A';
      case kAudioFormatMP3:
        return 'MP3';
      case kAudioFormatFLAC:
        return 'FLAC';
      case kAudioFormatWAV:
        return 'WAV';
      case kAudioFormatOGG:
        return 'OGG';
      default:
        return 'M4A';
    }
  }

  /// 是否为直拷格式（不需重编码）
  static bool audioFormatIsCopy(String format) {
    return format == kAudioFormatM4A;
  }

  /// 获取格式的简短描述
  static String audioFormatDescription(String format) {
    switch (format) {
      case kAudioFormatM4A:
        return '直拷复用，最快最无损';
      case kAudioFormatMP3:
        return '最通用的音频格式';
      case kAudioFormatFLAC:
        return '无损压缩，适合存档';
      case kAudioFormatWAV:
        return '未压缩，适合编辑';
      case kAudioFormatOGG:
        return '开源格式';
      default:
        return '';
    }
  }

  /// 获取格式对应的 FFmpeg 编码参数
  static List<String> audioFormatFfmpegArgs(String format) {
    switch (format) {
      case kAudioFormatM4A:
        return ['-c:a', 'copy', '-vn'];
      case kAudioFormatMP3:
        return ['-c:a', 'libmp3lame', '-q:a', '2', '-vn'];
      case kAudioFormatFLAC:
        return ['-c:a', 'flac', '-vn'];
      case kAudioFormatWAV:
        return ['-c:a', 'pcm_s16le', '-vn'];
      case kAudioFormatOGG:
        return ['-c:a', 'libvorbis', '-q:a', '4', '-vn'];
      default:
        return ['-c:a', 'copy', '-vn'];
    }
  }

  /// 所有音频文件扩展名列表（用于文件过滤）
  static List<String> get kAllAudioExtensions =>
      kSupportedAudioFormats.map(audioFormatExtension).toList();
}
