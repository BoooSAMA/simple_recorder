import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/modules/search/search_controller.dart';
import 'package:simple_recorder/services/db_service.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final LiveSearchController controller;
  late final TextEditingController searchCtl;

  @override
  void initState() {
    super.initState();
    controller = Get.put(LiveSearchController());
    searchCtl = TextEditingController();
  }

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: item.cover.isNotEmpty
                                ? Image.network(item.cover, fit: BoxFit.cover)
                                : Center(
                                    child: Text(
                                      item.userName.isNotEmpty ? item.userName[0] : "?",
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                          ),
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
