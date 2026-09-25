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

  /// 从文件名解析 `日期 + 开始时间` 键（如 "2026-09-05 22-13"），供
  /// “按文件名日期排序”比较。文件名格式 {owner}_{date}_{start}_{end}[后缀].ext，
  /// 贪婪匹配最后一个日期段，owner 含下划线也安全；格式不符返回 ""。
  static String parseNameDateKey(String fileName) {
    final m =
        RegExp(r'.*_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2})_').firstMatch(fileName);
    if (m == null) return "";
    return "${m.group(1)} ${m.group(2)}";
  }

  /// 按文件名日期比较（零填充固定格式可直接字符串比较），解析失败的沉底。
  /// [ascending] true=升序（旧→新），false=降序（新→旧）。
  static int compareNameDate(String a, String b, bool ascending) {
    final ka = parseNameDateKey(a);
    final kb = parseNameDateKey(b);
    if (ka.isEmpty && kb.isEmpty) return 0;
    if (ka.isEmpty) return 1;
    if (kb.isEmpty) return -1;
    final c = ka.compareTo(kb);
    return ascending ? c : -c;
  }
}
