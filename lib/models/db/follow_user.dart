import 'package:get/get.dart';
import 'package:hive/hive.dart';

part 'follow_user.g.dart';

@HiveType(typeId: 1)
class FollowUser {
  FollowUser({
    required this.id,
    required this.roomId,
    required this.siteId,
    required this.userName,
    required this.face,
    required this.addTime,
    this.tag = "全部",
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
  DateTime addTime;

  @HiveField(6)
  String tag;

  @HiveField(7)
  bool isPinned = false;

  Rx<int> liveStatus = 0.obs;
  String? liveStartTime;

  factory FollowUser.fromJson(Map<String, dynamic> json) => FollowUser(
        id: json['id'],
        roomId: json['roomId'],
        siteId: json['siteId'],
        userName: json['userName'],
        face: json['face'],
        addTime: DateTime.parse(json['addTime']),
        tag: json["tag"] ?? "全部",
      )..isPinned = json['isPinned'] ?? false;

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'siteId': siteId,
        'userName': userName,
        'face': face,
        'addTime': addTime.toString(),
        'tag': tag,
        'isPinned': isPinned,
      };
}
