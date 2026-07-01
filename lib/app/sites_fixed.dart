// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart' as hc;
import 'package:simple_live_core/src/scripts/douyin_sign.dart';

/// 修复 DouyinSite.searchRooms（缺少 X-Bogus 签名 + 使用了空 cookie）
class FixedDouyinSite extends DouyinSite {
  /// 搜索直播间 — 修复版
  /// 原版 douyin_site.dart:685 中的签名被注释掉了，
  /// 且手动 HEAD 请求获取的 cookie 可能为空。
  /// 此处改为 getRequestHeaders() + DouyinSign 签名。
  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "search_channel": "aweme_live",
        "keyword": keyword,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "from_group_id": "",
        "offset": ((page - 1) * 10).toString(),
        "count": "10",
        "pc_client_type": "1",
        "version_code": "170400",
        "version_name": "17.4.0",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "engine_name": "Blink",
        "engine_version": "125.0.0.0",
        "os_name": "Windows",
        "os_version": "10",
        "cpu_core_num": "12",
        "device_memory": "8",
        "platform": "PC",
        "downlink": "10",
        "effective_type": "4g",
        "round_trip_time": "100",
        "webid": "7382872326016435738",
      },
    );

    // Bug 1 修复：加上 X-Bogus 签名
    var requlestUrl = DouyinSign.getAbogusUrl(uri.toString(), DouyinSite.kDefaultUserAgent);

    // Bug 2 修复：使用 getRequestHeaders()（含已验证的 ttwid cookie）
    // 而非手动 HEAD 请求（后者 cookie 可能为空）
    var searchHeaders = Map<String, dynamic>.from(await getRequestHeaders());
    searchHeaders.addAll({
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'priority': 'u=1, i',
      'referer':
          'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
      'sec-ch-ua':
          '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
    });

    var result = await hc.HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: searchHeaders,
    );

    if (result == "" || result == 'blocked') {
      throw Exception("抖音直播搜索被限制，请稍后再试");
    }

    var items = <LiveRoomItem>[];
    for (var item in result["data"] ?? []) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomItem = LiveRoomItem(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        userName: itemData["owner"]["nickname"].toString(),
        online: int.tryParse(itemData["stats"]["total_user"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: items.length >= 10, items: items);
  }
}

/// 猫耳FM 站点实现
/// 猫耳FM没有公开的搜索API，搜索时尝试将关键字当作房间号查询
class MaoerfmSite implements LiveSite {
  static const String kBaseUrl = "https://fm.missevan.com";

  static const Map<String, dynamic> _headers = {
    "User-Agent":
        "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36",
    "Origin": kBaseUrl,
    "Referer": "$kBaseUrl/",
  };

  @override
  String id = "maoerfm";

  @override
  String name = "猫耳FM";

  @override
  LiveDanmaku getDanmaku() => LiveDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async => [];

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    // 提取关键字中的数字部分作为房间号
    var numMatch = RegExp(r'(\d+)').firstMatch(keyword.trim());
    if (numMatch != null) {
      var roomId = numMatch.group(1)!;
      try {
        var detail = await getRoomDetail(roomId: roomId);
        if (detail.roomId.isNotEmpty) {
          return LiveSearchRoomResult(
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
      } catch (_) {}
    }
    return LiveSearchRoomResult(hasMore: false, items: []);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    return LiveSearchAnchorResult(hasMore: false, items: []);
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: []);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: []);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var json = await hc.HttpClient.instance.getJson(
      "$kBaseUrl/api/v2/live/$roomId",
      header: _headers,
    );

    if (json['code'] != 0) {
      throw Exception(json['info'] ?? '获取房间信息失败');
    }

    var info = json['info'] as Map<String, dynamic>;
    var room = info['room'] as Map<String, dynamic>;
    var creator = info['creator'] as Map<String, dynamic>?;

    var status = room['status'] as Map<String, dynamic>? ?? {};
    var isLive = status['broadcasting'] == true || status['open'] == 1;

    var statistics = room['statistics'] as Map<String, dynamic>? ?? {};

    return LiveRoomDetail(
      roomId: room['room_id'].toString(),
      title: room['name']?.toString() ?? '',
      cover: room['cover_url']?.toString() ?? '',
      userName: creator?['username']?.toString() ??
          room['creator_username']?.toString() ??
          '',
      userAvatar: creator?['iconurl']?.toString() ?? '',
      online: int.tryParse(statistics['online']?.toString() ?? '0') ?? 0,
      status: isLive,
      url: "$kBaseUrl/live/${room['room_id']}",
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    return [
      LivePlayQuality(quality: "0", data: "audio", sort: 0),
    ];
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    var json = await hc.HttpClient.instance.getJson(
      "$kBaseUrl/api/v2/live/${detail.roomId}",
      header: _headers,
    );

    if (json['code'] != 0) {
      throw Exception(json['info'] ?? '获取播放地址失败');
    }

    var room = json['info']['room'] as Map<String, dynamic>;
    var channel = room['channel'] as Map<String, dynamic>? ?? {};
    var hlsUrl = channel['hls_pull_url']?.toString() ?? '';
    var flvUrl = channel['flv_pull_url']?.toString() ?? '';

    var urls = <String>[];
    if (hlsUrl.isNotEmpty) urls.add(hlsUrl);
    if (flvUrl.isNotEmpty) urls.add(flvUrl);

    if (urls.isEmpty) {
      throw Exception('获取播放地址失败');
    }

    return LivePlayUrl(urls: urls);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    try {
      var json = await hc.HttpClient.instance.getJson(
        "$kBaseUrl/api/v2/live/$roomId",
        header: _headers,
      );

      if (json['code'] != 0) return false;

      var room = json['info']['room'] as Map<String, dynamic>;
      var status = room['status'] as Map<String, dynamic>? ?? {};
      return status['broadcasting'] == true || status['open'] == 1;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) async {
    return [];
  }
}
