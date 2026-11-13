import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_recorder/app/controller/app_settings_controller.dart';
import 'package:simple_recorder/app/design_tokens.dart';
import 'package:simple_recorder/app/sites.dart';
import 'package:simple_recorder/app/log.dart';
import 'package:simple_recorder/models/db/follow_user.dart';
import 'package:simple_recorder/modules/home/home_controller.dart';
import 'package:simple_recorder/routes/route_path.dart';
import 'package:simple_recorder/services/global_player_controller.dart';
import 'package:simple_recorder/services/recording_manager.dart';
import 'package:simple_recorder/widgets/status_badge.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// 两列卡片网格：固定行高，让「录制中 / 未录制」两种卡片状态切换时网格不跳动
  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    mainAxisExtent: 158,
  );

  @override
  Widget build(BuildContext context) {
    var controller = Get.put(HomeController());
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const SizedBox.shrink(),
        leadingWidth: 48,
        leading: Obx(() {
          if (controller.isLoading.value) {
            final progress = controller.loadProgress.value;
            return Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 2.2,
                    ),
                    if (progress > 0)
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          return _TopAction(
            icon: Icons.refresh_rounded,
            tooltip: '刷新状态',
            onTap: () => controller.checkAllLiveStatus(notifyCleanup: true),
          );
        }),
        actions: [
          _TopAction(
            icon: Icons.folder_rounded,
            tooltip: '配置存储路径',
            onTap: () => Get.toNamed(RoutePath.kAudioSettings),
          ),
          _TopAction(
            icon: Icons.headphones_rounded,
            tooltip: '查看录音文件',
            onTap: () => Get.toNamed(RoutePath.kRecordings),
          ),
          _TopAction(
            icon: Icons.inventory_2_rounded,
            tooltip: 'TS 解包工具',
            onTap: () => Get.toNamed(RoutePath.kTsUnpack),
          ),
          _TopAction(
            icon: Icons.settings_rounded,
            tooltip: '设置',
            onTap: () => Get.toNamed(RoutePath.kSettings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // 右下角搜索 FAB（跳转键已搬回顶部栏）
      // 全局播放器显示时上移避让（收起态只需小避让）
      floatingActionButton: Obx(() {
        final c = GlobalPlayerController.instance;
        final lift = !c.isVisible ? 0 : (c.isCollapsed.value ? 60 : 250);
        return Padding(
          padding: EdgeInsets.only(bottom: lift.toDouble()),
          child: FloatingActionButton(
            heroTag: 'home_fab_search',
            tooltip: '搜索',
            onPressed: () => Get.toNamed(RoutePath.kSearch),
            child: const Icon(Icons.search),
          ),
        );
      }),
      body: Obx(() {
        if (controller.followList.isEmpty) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: AppSurface.chip(scheme),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.podcasts_rounded,
                      size: 36,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Text("还没有收藏的直播间", style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    "搜索主播并关注，开播状态会显示在这里",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  FilledButton.icon(
                    onPressed: () => Get.toNamed(RoutePath.kSearch),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text("搜索直播间"),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // 录制状态 + 一键操作条（有录制 / 有可录置顶时才占位）
            _buildActionBar(context, controller),
            _buildFilterBar(context, controller),
            Expanded(
              child: controller.filterMode.value == 0
                  ? _buildGroupedList(context, controller)
                  : _buildSimpleList(context, controller),
            ),
          ],
        );
      }),
    );
  }

  /// 录制状态 + 一键操作条。
  ///
  /// 左侧是"录制中 N/M"指示灯，右侧是「全录」「全停」胶囊按钮。
  /// 无录制且无置顶可操作时整条不占位，避免永久占据首屏。
  Widget _buildActionBar(BuildContext context, HomeController controller) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Obx(() {
      final recording = RecordingManager.instance.activeCount.value;
      final max = RecordingManager.instance.maxConcurrent;
      final ready = controller.pinnedReadyCount;
      final stopping = controller.pinnedRecordingCount;
      final loading = controller.isLoading.value;
      final showReady = ready > 0 && !loading;
      final showStop = stopping > 0 && !loading;
      if (recording == 0 && !showReady && !showStop) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.xs,
        ),
        child: Row(
          children: [
            if (recording > 0) ...[
              _RecordingLeds(count: recording, max: max),
              const SizedBox(width: AppSpace.sm),
              Text(
                "录制中 $recording/$max",
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const Spacer(),
            if (showReady)
              _ActionPill(
                icon: Icons.play_arrow_rounded,
                label: "全录 $ready",
                color: scheme.primary,
                onTap: () {
                  HapticFeedback.lightImpact();
                  controller.startAllPinnedRecordings();
                },
              ),
            if (showReady && showStop) const SizedBox(width: AppSpace.sm),
            if (showStop)
              _ActionPill(
                icon: Icons.stop_rounded,
                label: "全停 $stopping",
                color: scheme.error,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  controller.stopAllPinnedRecordings();
                },
              ),
          ],
        ),
      );
    });
  }

  /// 筛选栏：胶囊分段控件（选中实心主色），点击即时切换 + 触觉反馈
  Widget _buildFilterBar(BuildContext context, HomeController controller) {
    final theme = Theme.of(context);
    final liveCount = controller.liveList.length;
    final notLiveCount = controller.notLiveList.length;
    final allCount = controller.followList.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppSurface.header(theme.colorScheme),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _filterTab(context, '直播中', liveCount, 1, controller),
          const SizedBox(width: 6),
          _filterTab(context, '未开播', notLiveCount, 2, controller),
          const SizedBox(width: 6),
          _filterTab(context, '全部', allCount, 0, controller),
        ],
      ),
    );
  }

  Widget _filterTab(
    BuildContext context,
    String label,
    int count,
    int mode,
    HomeController controller,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Obx(() {
        final selected = controller.filterMode.value == mode;
        return AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: AppRadius.rPill,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.rPill,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: AppRadius.rPill,
              splashFactory: InkRipple.splashFactory,
              splashColor: selected
                  ? scheme.onPrimary.withAlpha(90)
                  : scheme.onSurface.withAlpha(45),
              highlightColor: Colors.transparent,
              onTap: () {
                if (selected) return;
                HapticFeedback.selectionClick();
                controller.setFilterMode(mode);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.onPrimary.withAlpha(40)
                              : scheme.onSurface.withAlpha(22),
                          borderRadius: AppRadius.rPill,
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// 分组列表：直播中 + 未开播 两个 section（2 列 Grid）
  Widget _buildGroupedList(BuildContext context, HomeController controller) {
    final liveItems = controller.liveList;
    final notLiveItems = controller.notLiveList;

    return RefreshIndicator(
      onRefresh: () => controller.checkAllLiveStatus(notifyCleanup: true),
      child: CustomScrollView(
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(bottom: 4)),
          if (liveItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context,
                '直播中',
                liveItems.length,
                icon: Icons.live_tv_rounded,
                tone: StatusTone.success,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.sm,
                AppSpace.md,
                AppSpace.xs,
              ),
              sliver: SliverGrid(
                gridDelegate: _gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RoomCard(
                    key: ValueKey(liveItems[i].id),
                    user: liveItems[i],
                  ),
                  childCount: liveItems.length,
                ),
              ),
            ),
          ],
          if (notLiveItems.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                context,
                '未开播',
                notLiveItems.length,
                icon: Icons.schedule_rounded,
                tone: StatusTone.neutral,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.sm,
                AppSpace.md,
                AppSpace.xs,
              ),
              sliver: SliverGrid(
                gridDelegate: _gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _RoomCard(
                    key: ValueKey(notLiveItems[i].id),
                    user: notLiveItems[i],
                  ),
                  childCount: notLiveItems.length,
                ),
              ),
            ),
          ],
          // 页底安全空白：避开系统导航条 + 右下角搜索 FAB，末行卡片不被遮挡
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 76),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    int count, {
    IconData? icon,
    StatusTone tone = StatusTone.neutral,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final fg = switch (tone) {
      StatusTone.success =>
        dark ? Colors.green.shade300 : Colors.green.shade700,
      StatusTone.primary => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
    return Material(
      color: AppSurface.header(scheme),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.dividerColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            StatusBadge('$count', tone: tone),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleList(BuildContext context, HomeController controller) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: () => controller.checkAllLiveStatus(notifyCleanup: true),
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.sm,
          AppSpace.md,
          AppSpace.sm + bottomInset,
        ),
        gridDelegate: _gridDelegate,
        itemCount: controller.filteredList.length,
        itemBuilder: (context, index) {
          var user = controller.filteredList[index];
          return _RoomCard(key: ValueKey(user.id), user: user);
        },
      ),
    );
  }
}

class _RoomCard extends StatefulWidget {
  final FollowUser user;

  const _RoomCard({super.key, required this.user});

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterController;
  // 置顶按钮的本地即时状态：先切图标并播放动画，再延迟重排列表，
  // 避免卡片瞬间移位导致用户看不到「钉子变了」的反馈。
  bool? _localPinned;
  bool _pinBusy = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      duration: AppMotion.slow,
      vsync: this,
    );
    _enterController.forward();
  }

  @override
  void dispose() {
    _enterController.dispose();
    super.dispose();
  }

  bool get _effectivePinned =>
      _localPinned ??
      AppSettingsController.instance.isFollowPinned(widget.user.id);

  Future<void> _togglePin() async {
    if (_pinBusy) return;
    _pinBusy = true;
    final next = !_effectivePinned;
    HapticFeedback.selectionClick();
    setState(() => _localPinned = next);
    if (mounted) {
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              next ? "已置顶，将优先展示" : "已取消置顶",
              style: TextStyle(color: scheme.onSurface, fontSize: 13),
            ),
            duration: const Duration(milliseconds: 1400),
            width: 240,
            backgroundColor: scheme.surfaceContainerHigh,
          ),
        );
    }
    try {
      await AppSettingsController.instance.toggleFollowPin(widget.user.id);
      // 让图标切换动画先被看到，再按「置顶优先」重排
      await Future.delayed(const Duration(milliseconds: 380));
    } finally {
      _pinBusy = false;
    }
    if (!mounted) return;
    setState(() => _localPinned = null);
    Get.find<HomeController>().filterData();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final controller = Get.find<HomeController>();
    final liveStatus = user.liveStatus.value;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPinned = _effectivePinned;

    final fade = CurvedAnimation(
      parent: _enterController,
      curve: AppMotion.enter,
    );
    final slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _enterController, curve: AppMotion.enter),
        );

    // 置顶 + 直播中：主色细描边 + 极轻光晕（替代原先刺眼的黄绿粗框）
    final highlight = isPinned && liveStatus == 2;

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            // 比工具条更轻的卡片底：保持页面干净，靠描边划分边界
            color: AppSurface.header(scheme),
            borderRadius: AppRadius.rLg,
            border: Border.all(
              color: highlight
                  ? scheme.primary.withAlpha(140)
                  : AppSurface.outline(scheme).withAlpha(56),
              width: highlight ? 1.2 : 0.7,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: scheme.primary.withAlpha(20),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：头像（直播中带绿环）+ 置顶 + 更多
              Row(
                children: [
                  _buildAvatar(context, user),
                  const Spacer(),
                  _buildPinButton(context, isPinned),
                  _buildMoreButton(context, controller, user),
                ],
              ),
              const SizedBox(height: 6),
              // 主播名称
              Text(
                user.userName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.25,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // 状态行：直播中 / 未开播 / 检查中 / 录制中·时长·大小
              _buildStatusLine(context, user, liveStatus),
              // 主操作固定贴底，两种状态切换不牵动上半区布局
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: _CompactRecordingControls(
                    liveStatus: liveStatus,
                    user: user,
                    controller: controller,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 状态行：小圆点 + 文字，一眼区分直播/未开播/检查中/录制中
  Widget _buildStatusLine(
    BuildContext context,
    FollowUser user,
    int liveStatus,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return Obx(() {
      final session = RecordingManager.instance.getSession(user.id);
      final recording = session?.isRecording.value ?? false;
      final duration = session?.duration.value ?? "00:00";
      final size = session?.fileSize.value ?? "";
      final lastError = session?.lastError.value ?? "";

      final Color color;
      final String label;
      if (recording) {
        color = scheme.error;
        label = lastError.isEmpty
            ? (size.isEmpty ? "录制 $duration" : "录制 $duration · $size")
            : "录制异常";
      } else if (liveStatus == 2) {
        color = dark ? Colors.green.shade400 : Colors.green.shade600;
        label = "直播中";
      } else if (liveStatus == 0) {
        color = Colors.amber.shade600;
        label = "检查中";
      } else {
        color = scheme.onSurface.withAlpha(120);
        label = "未开播";
      }

      final row = Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: liveStatus == 2 && !recording
                  ? [BoxShadow(color: color.withAlpha(90), blurRadius: 5)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: recording || liveStatus == 2
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (recording && lastError.isNotEmpty) ...[
            const SizedBox(width: 3),
            Icon(Icons.error_outline_rounded, size: 12, color: color),
          ],
          // 平台名：轻量补充信息，录制中不显示以免挤压时长
          if (!recording)
            Text(
              Sites.getSite(user.siteId)?.name ?? "",
              maxLines: 1,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                color: scheme.onSurface.withAlpha(100),
              ),
            ),
        ],
      );

      if (recording && lastError.isNotEmpty) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showDebugLog(context),
          child: row,
        );
      }
      return row;
    });
  }

  /// 头像：圆形 + 首字兜底 + 直播中绿色描边 + 右下角开播状态点
  Widget _buildAvatar(BuildContext context, FollowUser user) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final live = user.liveStatus.value == 2;
    final ringColor = (dark ? Colors.green.shade400 : Colors.green.shade600)
        .withAlpha(150);

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: EdgeInsets.all(live ? 2.5 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live ? ringColor : Colors.transparent,
              ),
              child: ClipOval(
                child: Container(
                  color: AppSurface.chip(scheme),
                  child: user.face.isNotEmpty
                      ? Image.network(
                          user.face,
                          fit: BoxFit.cover,
                          // 加载中先显示首字兜底，避免出现空白方块
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : _buildAvatarFallback(context, user),
                          errorBuilder: (_, _, _) =>
                              _buildAvatarFallback(context, user),
                        )
                      : _buildAvatarFallback(context, user),
                ),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: _StatusIndicator(liveStatus: user.liveStatus.value),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(BuildContext context, FollowUser user) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        user.userName.isNotEmpty ? user.userName[0] : '?',
        style: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPinButton(BuildContext context, bool isPinned) {
    final scheme = Theme.of(context).colorScheme;
    return _Pressable(
      borderRadius: AppRadius.rSm,
      haptic: false,
      onTap: _togglePin,
      child: SizedBox(
        width: 36,
        height: 36,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            key: ValueKey(isPinned),
            size: 19,
            color: isPinned
                ? Colors.amber.shade500
                : scheme.onSurfaceVariant.withAlpha(130),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreButton(
    BuildContext context,
    HomeController controller,
    FollowUser user,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return _Pressable(
      borderRadius: AppRadius.rSm,
      haptic: false,
      onTap: () {
        HapticFeedback.selectionClick();
        final box = context.findRenderObject() as RenderBox?;
        final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(pos.dx - 128, pos.dy + 36, 0, 0),
          items: [
            const PopupMenuItem(
              value: "delete",
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Text("取消关注"),
                ],
              ),
            ),
            const PopupMenuItem(
              value: "live_duration",
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 18),
                  SizedBox(width: 8),
                  Text("获取开播信息"),
                ],
              ),
            ),
          ],
        ).then((value) {
          if (value == "delete") {
            controller.removeFollow(user);
          } else if (value == "live_duration") {
            controller.getLiveDuration(user);
          }
        });
      },
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 19,
          color: scheme.onSurfaceVariant.withAlpha(150),
        ),
      ),
    );
  }
}

/// 录制控制按钮（全宽行，含录制时长信息）
class _CompactRecordingControls extends StatelessWidget {
  final int liveStatus;
  final FollowUser user;
  final HomeController controller;

  const _CompactRecordingControls({
    required this.liveStatus,
    required this.user,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final _ = RecordingManager.instance.activeSessions.length;
      final session = RecordingManager.instance.getSession(user.id);
      final isRecording = session?.isRecording.value ?? false;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final dark = theme.brightness == Brightness.dark;

      if (isRecording) {
        final errorColor = scheme.error;
        return Row(
          children: [
            // 停止按钮（实心 error，主操作）
            Expanded(
              child: _Pressable(
                borderRadius: AppRadius.rPill,
                haptic: false,
                color: errorColor,
                splashColor: scheme.onError.withAlpha(70),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  controller.stopRecording(user);
                },
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(borderRadius: AppRadius.rPill),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stop_rounded, color: scheme.onError, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        "停止",
                        style: TextStyle(
                          color: scheme.onError,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 取消按钮（图标按钮，低频操作降噪）
            _Pressable(
              borderRadius: AppRadius.rPill,
              haptic: false,
              onTap: () {
                HapticFeedback.mediumImpact();
                controller.cancelRecording(user);
              },
              child: Container(
                width: 40,
                height: 32,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: errorColor.withAlpha(110),
                    width: 1,
                  ),
                  borderRadius: AppRadius.rPill,
                ),
                child: Icon(Icons.close_rounded, color: errorColor, size: 17),
              ),
            ),
          ],
        );
      }

      final isLive = liveStatus == 2;
      final isUnknown = liveStatus == 0;

      final Color fg;
      final Color? bg;
      final Color? border;
      if (isLive) {
        // 直播中：实心主色，一眼看出「可以录」
        fg = scheme.onPrimary;
        bg = scheme.primary;
        border = null;
      } else if (isUnknown) {
        fg = Colors.amber.shade600;
        bg = Colors.transparent;
        border = Colors.amber.shade600.withAlpha(dark ? 90 : 70);
      } else {
        // 未开播：幽灵描边按钮，视觉负担最轻
        fg = scheme.onSurfaceVariant.withAlpha(dark ? 160 : 140);
        bg = Colors.transparent;
        border = scheme.onSurface.withAlpha(dark ? 40 : 30);
      }

      return _Pressable(
        borderRadius: AppRadius.rPill,
        haptic: false,
        color: bg,
        splashColor: isLive ? scheme.onPrimary.withAlpha(70) : null,
        onTap: () {
          HapticFeedback.lightImpact();
          controller.toggleRecording(user);
        },
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            borderRadius: AppRadius.rPill,
            border: border == null
                ? null
                : Border.all(color: border, width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isLive ? Icons.mic_rounded : Icons.mic_off_rounded,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 5),
              Text(
                isUnknown ? "检查中" : (isLive ? "录制" : "未开播"),
                style: TextStyle(
                  color: fg,
                  fontWeight: isLive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// 录制中调试日志面板（响应式）
void _showDebugLog(BuildContext context) {
  Get.dialog(
    AlertDialog(
      title: const Text("调试日志"),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: Log.debugLogs.reversed.take(50).map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                "[${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}] ${entry.message}",
                style: TextStyle(
                  fontSize: 11,
                  color: entry.color,
                  fontFamily: 'monospace',
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text("关闭")),
      ],
    ),
  );
}

class _StatusIndicator extends StatelessWidget {
  final int liveStatus;

  const _StatusIndicator({required this.liveStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final Color color;
    final bool glow;
    switch (liveStatus) {
      case 2:
        // 直播中：亮绿 + 柔和光晕
        color = dark ? Colors.green.shade400 : Colors.green.shade600;
        glow = true;
        break;
      case 0:
        // 检查中：琥珀色，与「未开播」区分
        color = Colors.amber.shade600;
        glow = false;
        break;
      default:
        // 未开播：低对比灰点
        color = scheme.onSurface.withAlpha(100);
        glow = false;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppSurface.chip(scheme), width: 2),
        boxShadow: glow
            ? [BoxShadow(color: color.withAlpha(90), blurRadius: 6)]
            : null,
      ),
    );
  }
}

/// 顶部工具栏图标：44×44 触摸区 + 20px 图标 + 按压缩放反馈
class _TopAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        borderRadius: AppRadius.rPill,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

/// 通用按压反馈：Material 波纹（InkWell）+ 触觉反馈。
/// 所有自绘点击区域统一走这里，保证「点下去立刻有反应」。
/// [color] 用于自带底色的按钮：底色画在 Material 上，波纹才能显示在底色之上。
class _Pressable extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool haptic;
  final Color? color;
  final Color? splashColor;

  const _Pressable({
    required this.child,
    this.onTap,
    this.borderRadius = AppRadius.rPill,
    this.haptic = true,
    this.color,
    this.splashColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final splash = splashColor ?? scheme.onSurface.withAlpha(45);
    return Material(
      color: color ?? Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        splashFactory: InkRipple.splashFactory,
        splashColor: splash,
        highlightColor: Colors.transparent,
        onTap: onTap == null
            ? null
            : () {
                if (haptic) HapticFeedback.selectionClick();
                onTap!.call();
              },
        child: child,
      ),
    );
  }
}

/// 录制指示灯：最多 5 个圆点，亮起数 = 当前录制数（超过 5 路时全亮）
class _RecordingLeds extends StatelessWidget {
  final int count;
  final int max;

  const _RecordingLeds({required this.count, required this.max});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final active = dark ? Colors.green.shade400 : Colors.green.shade600;
    final idle = theme.colorScheme.onSurface.withAlpha(38);
    final shown = max > 5 ? 5 : (max < 1 ? 1 : max);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(shown, (i) {
        final on = i < count;
        return Container(
          width: 7,
          height: 7,
          margin: EdgeInsets.only(right: i == shown - 1 ? 0 : 3),
          decoration: BoxDecoration(
            color: on ? active : idle,
            shape: BoxShape.circle,
            boxShadow: on
                ? [BoxShadow(color: active.withAlpha(70), blurRadius: 4)]
                : null,
          ),
        );
      }),
    );
  }
}

/// 一键操作胶囊按钮（全录 / 全停），tonal 底 + 同色描边
class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _Pressable(
      borderRadius: AppRadius.rPill,
      onTap: onTap,
      haptic: false, // 调用方带自己的触觉强度
      color: color.withAlpha(dark ? 46 : 26),
      splashColor: color.withAlpha(dark ? 90 : 60),
      child: Container(
        height: 40,
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: AppRadius.rPill,
            border: Border.all(
              color: color.withAlpha(dark ? 110 : 80),
              width: 0.9,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
