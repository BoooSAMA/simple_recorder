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

    // 如果关键词是纯数字（疑似房间号/WebRid），再通过 getRoomDetail 精确查找
    // 抖音搜索API只返回正在直播的直播间，且不支持按房间号搜索。
    // 通过 getRoomDetail 可以搜到该主播（不管是否在直播）。
    var numMatch = RegExp(r'^\d{6,}$').firstMatch(keyword.trim());
    if (numMatch != null) {
      var roomId = numMatch.group(0)!;
      try {
        var detail = await getRoomDetail(roomId: roomId);
        if (detail.roomId.isNotEmpty &&
            !items.any((i) => i.roomId == detail.roomId)) {
          items.insert(
            0,
            LiveRoomItem(
              roomId: detail.roomId,
              title: detail.title.isNotEmpty ? detail.title : "房间号: $roomId",
              cover: detail.cover,
              userName: detail.userName,
              online: detail.online,
            ),
          );
        }
      } catch (_) {
        // getRoomDetail 失败不影响正常搜索结果
      }
    }

    // 【新增】直播搜索为空时，尝试通用搜索 fallback
    // 抖音直播搜索只返回当前正在直播的直播间。通用搜索可以搜到
    // 主播资料页（无论是否在直播），弥补直播搜索的盲区。
    if (items.isEmpty) {
      try {
        var generalItems = await _searchGeneral(keyword);
        for (var gi in generalItems) {
          if (!items.any((i) => i.roomId == gi.roomId)) {
            items.add(gi);
          }
        }
      } catch (_) {
        // 通用搜索失败不影响正常返回
      }
    }

    return LiveSearchRoomResult(hasMore: items.length >= 10, items: items);
  }

  /// 通用搜索 fallback — 调用抖音综合搜索 API
  /// 当直播搜索返回空时使用，可以搜到未开播主播的资料页。
  /// 如果主播的资料页中带有直播间 ID（room_id/web_rid），
  /// 则返回其为 LiveRoomItem，方便用户收藏。
  Future<List<LiveRoomItem>> _searchGeneral(String keyword) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/general/search/single/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "keyword": keyword,
        "search_channel": "aweme_general",
        "search_source": "normal_search",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "offset": "0",
        "count": "15",
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
      },
    );

    var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), DouyinSite.kDefaultUserAgent);
    var searchHeaders = Map<String, dynamic>.from(await getRequestHeaders());
    searchHeaders.addAll({
      'accept': 'application/json, text/plain, */*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'priority': 'u=1, i',
      'referer':
          'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=general',
      'sec-ch-ua':
          '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
    });

    var result = await hc.HttpClient.instance.getJson(
      requestUrl,
      queryParameters: {},
      header: searchHeaders,
    );

    if (result is! Map || result["status_code"] != 0) {
      return [];
    }

    var items = <LiveRoomItem>[];
    var dataList = result["data"];
    if (dataList is! List) return [];

    for (var entry in dataList) {
      if (entry is! Map) continue;
      try {
        // 尝试多种可能的用户信息结构
        LiveRoomItem? roomItem;

        // 结构 1: { "type": 2, "user": { ... } }
        if (entry["user"] is Map) {
          roomItem = _parseUserSearchEntry(entry["user"]);
        }
        // 结构 2: { "type": 2, "user_info": { ... } }
        else if (entry["user_info"] is Map) {
          roomItem = _parseUserSearchEntry(entry["user_info"]);
        }
        // 结构 3: { "type": 2, "user_list": [...] }
        else if (entry["user_list"] is List) {
          for (var u in entry["user_list"]) {
            if (u is! Map) continue;
            var userData = u;
            if (userData["user_info"] is Map) {
              userData = userData["user_info"] as Map<dynamic, dynamic>;
            }
            var ri = _parseUserSearchEntry(userData);
            if (ri != null) items.add(ri);
          }
        }

        if (roomItem != null) items.add(roomItem);
      } catch (_) {
        // 单条解析失败跳过
      }
    }

    return items;
  }

  /// 从通用搜索的用户条目中提取 LiveRoomItem
  /// 抖音用户的资料页中可能包含 room_id（临时房间号）或
  /// web_rid（永久房间号）。只要拿到任意一个即可。
  LiveRoomItem? _parseUserSearchEntry(Map data) {
    // 尝试提取 room_id / web_rid
    var roomId = data["room_id"]?.toString() ?? "";
    var webRid = data["web_rid"]?.toString() ?? "";

    // 部分响应有嵌套 room 对象
    if (roomId.isEmpty && data["room"] is Map) {
      roomId = (data["room"]["id_str"] ?? data["room"]["id"] ?? "").toString();
    }
    if (webRid.isEmpty && data["room"] is Map) {
      webRid = (data["room"]["web_rid"] ?? "").toString();
    }

    var finalRoomId = webRid.isNotEmpty ? webRid : roomId;
    if (finalRoomId.isEmpty) return null;

    // 提取昵称
    var nickname = data["nickname"]?.toString() ?? "";

    // 提取头像（作为封面）
    var avatar = data["avatar"]?.toString() ?? "";
    if (avatar.isEmpty && data["avatar_thumb"] is Map) {
      var list = data["avatar_thumb"]["url_list"];
      if (list is List && list.isNotEmpty) {
        avatar = list[0].toString();
      }
    }
    if (avatar.isEmpty && data["avatar_larger"] is Map) {
      var list = data["avatar_larger"]["url_list"];
      if (list is List && list.isNotEmpty) {
        avatar = list[0].toString();
      }
    }
    // 兜底：cover 字段
    if (avatar.isEmpty) {
      avatar = data["cover"]?.toString() ?? "";
    }

    // 观众数：可能不在用户资料中
    var online = 0;
    try {
      online = int.tryParse(data["room_view_stats"]?["display_value"]?.toString() ?? "") ?? 0;
    } catch (_) {}

    return LiveRoomItem(
      roomId: finalRoomId,
      title: "房间号: $finalRoomId",
      cover: avatar,
      userName: nickname,
      online: online,
    );
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
    var urls = <String>[];

    // channel 可能是字符串（直接 URL），也可能是 dict {hls_pull_url, flv_pull_url}
    var channel = room['channel'];
    if (channel is String) {
      urls.add(channel);
    } else if (channel is Map) {
      var hlsUrl = channel['hls_pull_url']?.toString() ?? '';
      var flvUrl = channel['flv_pull_url']?.toString() ?? '';

      // FLV 优先：HLS 流在部分 CDN 上返回 403 Forbidden
      // 参考 DouyinLiveRecorder 项目优化方案
      if (flvUrl.isNotEmpty) urls.add(flvUrl);
      if (hlsUrl.isNotEmpty) urls.add(hlsUrl);
    }

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
