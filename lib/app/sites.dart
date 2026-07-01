import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_recorder/app/constant.dart';
import 'package:simple_recorder/app/sites_fixed.dart';

class Sites {
  static final Map<String, Site> allSites = {
    Constant.kBiliBili: Site(
      id: Constant.kBiliBili,
      logo: "",
      name: "哔哩哔哩",
      liveSite: BiliBiliSite(),
    ),
    Constant.kDouYin: Site(
      id: Constant.kDouYin,
      logo: "",
      name: "抖音",
      liveSite: FixedDouyinSite(),
    ),
    Constant.kDouYu: Site(
      id: Constant.kDouYu,
      logo: "",
      name: "斗鱼",
      liveSite: DouyuSite(),
    ),
    Constant.kHuYa: Site(
      id: Constant.kHuYa,
      logo: "",
      name: "虎牙",
      liveSite: HuyaSite(),
    ),
    Constant.kMaoerfm: Site(
      id: Constant.kMaoerfm,
      logo: "",
      name: "猫耳FM",
      liveSite: MaoerfmSite(),
    ),
  };

  static List<Site> get supportSites {
    return allSites.values.toList();
  }

  static Site? getSite(String id) {
    return allSites[id];
  }
}

class Site {
  final String id;
  final String name;
  final String logo;
  final LiveSite liveSite;

  Site({
    required this.id,
    required this.liveSite,
    required this.logo,
    required this.name,
  });
}
