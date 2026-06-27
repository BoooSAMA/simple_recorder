import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/services/db_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchController extends GetxController {
  final searchResults = RxList<LiveRoomItem>();
  final searchAnchorResults = RxList<LiveAnchorItem>();
  final isSearching = false.obs;
  final hasMore = true.obs;
  final selectedSiteId = Sites.supportSites.first.id.obs;
  int _page = 1;

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
      }
      hasMore.value = result.hasMore;
      _page++;
    } catch (e) {
      Get.snackbar("搜索失败", e.toString());
    } finally {
      isSearching.value = false;
    }
  }

  Future<void> followRoom(LiveRoomItem item) async {
    var id = "${selectedSiteId.value}_${item.roomId}";
    if (DBService.instance.getFollowExist(id)) {
      Get.snackbar("提示", "已收藏该直播间");
      return;
    }
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: item.roomId,
        siteId: selectedSiteId.value,
        userName: item.userName,
        face: item.cover,
        addTime: DateTime.now(),
      ),
    );
    Get.snackbar("成功", "已收藏「${item.userName}」");
  }
}

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(SearchController());
    var searchCtl = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: const Text("搜索直播间"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchCtl,
                    decoration: InputDecoration(
                      hintText: "搜索主播/房间",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (value) => controller.search(value),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: Sites.supportSites.map((site) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Obx(() {
                    var selected = controller.selectedSiteId.value == site.id;
                    return FilterChip(
                      label: Text(site.name),
                      selected: selected,
                      onSelected: (_) {
                        controller.changeSite(site.id);
                        if (searchCtl.text.isNotEmpty) {
                          controller.search(searchCtl.text);
                        }
                      },
                    );
                  }),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (controller.isSearching.value && controller.searchResults.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (controller.searchResults.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.radio_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text("搜索你想录制的主播", style: Theme.of(context).textTheme.bodyLarge),
                    ],
                  ),
                );
              }

              return NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200
                      && controller.hasMore.value
                      && !controller.isSearching.value) {
                    controller.search(searchCtl.text, loadMore: true);
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: controller.searchResults.length,
                  itemBuilder: (context, index) {
                    var item = controller.searchResults[index];
                    var isFollowed = DBService.instance.getFollowExist(
                      "${controller.selectedSiteId.value}_${item.roomId}",
                    );

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundImage: item.cover.isNotEmpty
                              ? NetworkImage(item.cover)
                              : null,
                          child: item.cover.isEmpty ? Text(item.userName[0]) : null,
                        ),
                        title: Text(item.userName),
                        subtitle: Text(
                          item.title.isNotEmpty ? item.title : "房间号: ${item.roomId}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            isFollowed ? Icons.star : Icons.star_border,
                            color: isFollowed ? Colors.amber : null,
                          ),
                          onPressed: isFollowed
                              ? null
                              : () => controller.followRoom(item),
                        ),
                        onTap: () => controller.followRoom(item),
                      ),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
