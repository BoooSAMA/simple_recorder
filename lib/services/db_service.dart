import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/models/db/recording_task.dart';

class DBService extends GetxService {
  static DBService get instance => Get.find<DBService>();

  late Box<FollowUser> _followBox;
  late Box<RecordingTask> _recordingBox;

  Future<void> init() async {
    _followBox = await Hive.openBox<FollowUser>("follow_users");
    _recordingBox = await Hive.openBox<RecordingTask>("recording_tasks");
  }

  List<FollowUser> getFollowList() {
    var list = _followBox.values.toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.addTime.compareTo(a.addTime);
    });
    return list;
  }

  Future<void> pinFollow(String id) async {
    var user = _followBox.get(id);
    if (user != null) {
      user.isPinned = true;
      await _followBox.put(id, user);
    }
  }

  Future<void> unpinFollow(String id) async {
    var user = _followBox.get(id);
    if (user != null) {
      user.isPinned = false;
      await _followBox.put(id, user);
    }
  }

  bool getFollowExist(String id) {
    return _followBox.containsKey(id);
  }

  Future<void> addFollow(FollowUser user) async {
    await _followBox.put(user.id, user);
  }

  Future<void> deleteFollow(String id) async {
    await _followBox.delete(id);
  }

  Future<void> updateFollowLiveStatus(String id, int status) async {
    var user = _followBox.get(id);
    if (user != null) {
      user.liveStatus.value = status;
      await _followBox.put(id, user);
    }
  }

  Future<void> addOrUpdateRecordingTask(RecordingTask task) async {
    await _recordingBox.put(task.id, task);
  }

  RecordingTask? getRecordingTask(String id) {
    return _recordingBox.get(id);
  }

  List<RecordingTask> getRecordingTaskList() {
    return _recordingBox.values.toList();
  }

  Future<void> deleteRecordingTask(String id) async {
    await _recordingBox.delete(id);
  }
}
