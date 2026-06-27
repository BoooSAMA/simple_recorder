import 'package:get/get.dart';
import 'package:hive/hive.dart';

part 'recording_task.g.dart';

@HiveType(typeId: 3)
class RecordingTask {
  RecordingTask({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.title,
    required this.addTime,
    this.outputPath = "",
    this.duration = "",
    this.fileSize = "",
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String roomId;

  @HiveField(2)
  String siteId;

  @HiveField(3)
  String userName;

  @HiveField(4)
  String face;

  @HiveField(5)
  String title;

  @HiveField(6)
  DateTime addTime;

  @HiveField(7)
  String outputPath;

  @HiveField(8)
  String duration;

  @HiveField(9)
  String fileSize;

  RxBool isRecording = false.obs;
  RxString currentDuration = "00:00".obs;
  RxString currentFileSize = "".obs;
  RxInt retryCount = 0.obs;
  RxString lastError = "".obs;

  factory RecordingTask.fromJson(Map<String, dynamic> json) => RecordingTask(
        id: json['id'],
        roomId: json['roomId'],
        siteId: json['siteId'],
        userName: json['userName'],
        face: json['face'],
        title: json['title'],
        addTime: DateTime.parse(json['addTime']),
        outputPath: json['outputPath'] ?? "",
        duration: json['duration'] ?? "",
        fileSize: json['fileSize'] ?? "",
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'siteId': siteId,
        'userName': userName,
        'face': face,
        'title': title,
        'addTime': addTime.toString(),
        'outputPath': outputPath,
        'duration': duration,
        'fileSize': fileSize,
      };
}
