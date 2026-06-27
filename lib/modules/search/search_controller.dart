import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/event_bus.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class LiveSearchController extends GetxController {
  final searchResults = RxList<LiveRoomItem>();
  final searchAnchorResults = RxList<LiveAnchorItem>();
  final isSearching = false.obs;
  final hasMore = true.obs;
  final selectedSiteId = Sites.supportSites.first.id.obs;

  /// roomId -> 主播头像URL（从房间详情异步获取）
  final avatarMap = RxMap<String, String>();

  /// 已收藏的房间 ID 集合（响应式，点击后即时变红）
  final followedIds = <String>{}.obs;

  int _page = 1;

  /// 是否正在获取头像
  final isLoadingAvatars = false.obs;

  @override
  void onInit() {
    super.onInit();
    // 初始化时加载已收藏的房间 ID 集合
    _loadFollowedIds();
  }

  /// 从数据库加载已收藏的房间 ID
  void _loadFollowedIds() {
    final list = DBService.instance.getFollowList();
    // ignore: invalid_use_of_protected_member
    followedIds.value = list.map((u) => u.id).toSet();
  }

  /// 检查房间是否已收藏
  bool isFollowed(String id) => followedIds.contains(id);

  void changeSite(String siteId) {
    selectedSiteId.value = siteId;
  }

  Future<void> search(String keyword, {bool loadMore = false}) async {
    if (keyword.isEmpty) return;

    if (!loadMore) {
      _page = 1;
      searchResults.clear();
      searchAnchorResults.clear();
    }

    isSearching.value = true;

    var site = Sites.getSite(selectedSiteId.value);
    if (site == null) {
      isSearching.value = false;
      return;
    }

    try {
      var result = await site.liveSite.searchRooms(keyword, page: _page);

      // 猫耳FM没有搜索API，尝试直接按房间号查询
      if (result.items.isEmpty && site.id == Constant.kMaoerfm) {
        var roomId = keyword.trim();
        if (RegExp(r'^\d+$').hasMatch(roomId)) {
          try {
            var detail = await site.liveSite.getRoomDetail(roomId: roomId);
            if (detail.roomId.isNotEmpty) {
              result = LiveSearchRoomResult(
                hasMore: false,
                items: [
                  LiveRoomItem(
                    roomId: detail.roomId,
                    title: detail.title,
                    cover: detail.cover,
                    userName: detail.userName,
                    online: detail.online,
                  ),
                ],
              );
            }
          } catch (_) {
            // 房间号查询失败，保持空结果
          }
        }
      }

      if (loadMore) {
        searchResults.addAll(result.items);
      } else {
        searchResults.value = result.items;
        avatarMap.clear();
      }
      hasMore.value = result.hasMore;
      _page++;

      // 异步拉取主播头像（不阻塞 UI）
      _fetchAvatars(result.items);
    } catch (e) {
      Get.snackbar("搜索失败", e.toString());
    } finally {
      isSearching.value = false;
    }
  }

  /// 并行拉取搜索结果的真实主播头像
  Future<void> _fetchAvatars(List<LiveRoomItem> items) async {
    if (items.isEmpty) return;
    isLoadingAvatars.value = true;

    var site = Sites.getSite(selectedSiteId.value);
    if (site == null) return;

    // 分批并发，每批最多 5 个
    const batchSize = 5;
    for (var i = 0; i < items.length; i += batchSize) {
      var batch = items.sublist(
        i,
        i + batchSize > items.length ? items.length : i + batchSize,
      );
      await Future.wait(batch.map((item) async {
        try {
          var detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
          if (detail.userAvatar.isNotEmpty) {
            avatarMap[item.roomId] = detail.userAvatar;
          }
        } catch (_) {
          // 单个获取失败不影响其他
        }
      }));
    }

    isLoadingAvatars.value = false;
  }

  /// 收藏直播间，同时获取主播真实头像
  Future<void> followRoom(LiveRoomItem item) async {
    var id = "${selectedSiteId.value}_${item.roomId}";
    if (DBService.instance.getFollowExist(id)) {
      Get.snackbar("提示", "已收藏该直播间");
      return;
    }

    // 优先从房间详情获取主播真实头像（LiveRoomItem.cover 是直播间封面，不是头像）
    var face = item.cover; // fallback: 使用封面
    var site = Sites.getSite(selectedSiteId.value);
    if (site != null) {
      try {
        var detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
        if (detail.userAvatar.isNotEmpty) {
          face = detail.userAvatar;
        }
      } catch (_) {
        // 获取详情失败则使用封面作为兜底
      }
    }

    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: item.roomId,
        siteId: selectedSiteId.value,
        userName: item.userName,
        face: face,
        addTime: DateTime.now(),
      ),
    );

    // 立即更新响应式集合，让心形图标即时变红
    followedIds.add(id);

    // 通知主页刷新收藏列表
    EventBus.instance.emit(Constant.kUpdateFollow, id);

    Get.snackbar("成功", "已收藏「${item.userName}」");
  }
}
