# Simple Recorder

> **多平台直播音频录制工具** — 基于 Flutter 构建，支持 Bilibili / 抖音 / 斗鱼 / 虎牙 / 猫耳FM 多平台直播间音频录制。
>
> **录播仅限自用，禁止将录播文件分发至网上。**

## 项目背景

本项目结合了两个开源项目的核心能力：

- **[Simple Live (dart_simple_live)](https://github.com/xiaoyaocz/dart_simple_live)** — 提供多平台直播搜索与房间信息获取能力
- **[Bililive](https://github.com/BoooSAMA/bililive)** — 提供基于 FFmpeg 的直播间音频录制核心功能

## 快速上手

### 第一步：首次安装

```bash
# 1. 克隆项目
git clone https://github.com/your/simple_recorder.git
cd simple_recorder

# 2. 获取依赖
flutter pub get

# 3. 生成 Hive 适配器
dart run build_runner build --delete-conflicting-outputs

# 4. 运行
flutter run
```

> Android 首次启动会自动请求"管理所有文件"权限（Android 11+）和"通知"权限（Android 13+），请允许以确保前台录制正常。

### 第二步：设置存储路径

1. 启动 app → 右下角 **齿轮图标** 进入设置
2. 点击 **音频存储路径** → 选择或输入你想要的录音保存目录
3. 建议开启 **按主播名分文件夹**，录制文件会自动归类

### 第三步：搜索并收藏主播

1. 首页顶部点击 **🔍 搜索图标** 进入搜索页
2. 选择平台（Bilibili / 抖音 / 斗鱼 / 虎牙 / 猫耳FM）
3. 输入主播昵称（猫耳FM 需输入房间号数字）→ 搜索
4. 结果列表中点击右侧 **♡ 心形图标** 收藏 → 即时变红，主播出现在首页

> 已收藏的主播也可以在此页面一键取消收藏。

### 第四步：查看直播状态

1. 回到首页，点击左上角 **🔄 刷新按钮**（带环形进度提示）
2. 系统会逐个检测所有收藏主播的直播状态：
   - 🟢 **直播中** — 绿色高亮，显示在列表上方
   - ⚫ **未开播** — 灰色，收在下方
3. 顶部筛选栏可切换视图：**直播中** / **未开播** / **全部**

### 第五步：置顶常用主播

1. 在卡片列表中找到常用主播
2. 点击右下角 **📌 图钉按钮** 置顶
3. 置顶后的主播卡片显示 **绿色边框**，始终排在列表最前面

> 置顶操作会同步到直播状态轮询（后台每 3 分钟自动检测），开播时发送通知。

### 第六步：开始录制

#### 方式 A：单个录制

点击主播卡片上的 **🎙️ 录制按钮** → 卡片变为红色录制态，实时显示：
- **时长** — 已录制时间（时:分:秒）
- **文件大小** — 已录制数据量
- **状态** — 正常录制 / 重连中(N/3) / 错误日志

#### 方式 B：一键批量录制（推荐）

当你有多个置顶主播同时直播时，顶部 AppBar 会出现 **● 一键录制** 按钮：

1. 按钮右侧会显示可录制数量 → 点击即开始
2. 系统**逐个启动**（不是同时），避免网络突发
3. 进度圈跟随更新，完成后弹出汇总：`成功启动: 4 | 跳过/失败: 0`

> 已开播但不在录制中的才会被启动，已在录制的自动跳过。

### 第七步：录制中的管理

- **停止** — 点击红色 **停止按钮** → 自动保存当前 TS 文件并解包为 M4A
- **取消（不保存）** — 点击 **取消按钮** → 弹出确认对话框 → 删除已录制的 TS 文件
- **一键结束** — 当有置顶录制运行时，AppBar 显示 **■ 停止按钮** → 一键结束所有

> 录制过程中切换 app 到后台不受影响，Android 前台服务会保活。

### 第八步：查看与管理录音

1. AppBar 点击 **⋮ 菜单** → **录音文件浏览**
2. 文件按 **主播名文件夹** 分组展示，清晰易找
3. 点击文件即可 **播放预览**（内置播放器）
4. 支持 **重命名**、**删除**、**批量删除**

#### 音频裁剪

在播放器界面底部，可以使用 **针筒滑块** 精确裁剪录音片段：

1. 拖动滑块选择裁剪起止位置
2. 点击裁剪 → 自动调用 FFmpeg 生成裁剪后的新文件
3. 原始文件不受影响

### 第九步：TS 解包（异常处理）

正常录制的文件在停止时会**自动解包**为 M4A。如果你看到 `.ts` 文件残留：

1. AppBar → **⋮ 菜单** → **TS 解包**
2. 文件按主播名分组展示，支持 **跨文件夹多选**
3. 勾选后点击批量解包 → 进度条跟随 → 完成后自动删除原始 TS
4. 文件名带 `_interrupted` 标记的是异常中断文件，同样支持解包

> App 每次启动时会自动扫描并标记异常中断的 TS 文件，无需手动处理。

### 第十步：进阶设置

| 设置项 | 位置 | 说明 |
|---|---|---|
| 主题/强调色 | 设置 → 外观 | 亮色/暗色 + 动态色 + 自定义色 |
| 音频格式 | 设置 → 音频输出格式 | M4A / MP3 / FLAC / WAV / OGG |
| 导出关注数据 | 设置 → 数据 | JSON 格式，兼容 Bililive |
| 调试日志 | 设置 → 调试日志 | 实时查看、保存、清空录制日志 |

## 功能特性

### 🎙️ 录制核心

- **多平台支持** — Bilibili、抖音、斗鱼、虎牙、猫耳FM 五大平台
- **纯音频录制** — 基于 FFmpeg 仅录制音频流 (c:a copy, 不重编码)，节省存储空间
- **并行录制** — 最多同时录制 20 个直播间，互不干扰
- **断线自动重连** — 录制中断自动重试（最多 3 次，退避延迟 2s/4s/6s）
- **FFmpeg TS 格式封装** — 录制时暂存为 TS 片段，停止后自动合成为 M4A 文件
- **后台持续录制** — 支持 app 切到后台后持续录制
- **前台服务保活** — Android 录制时启动前台服务通知，防止系统杀死后台进程
- **唤醒锁共享** — 多个录制共享一个唤醒锁，引用计数管理，省电不冲突

### 📡 直播状态监测

- **分批并发检测** — 每批 5 个直播间并行查询，避免阻塞 UI
- **渐进式 UI 更新** — 每完成一个立即同步到列表，无需等全量刷新
- **实时进度反馈** — 刷新按钮内置环形进度 + 百分比文字
- **分组筛选栏** — 直播中 / 未开播 / 全部 三种视图，带数量 badge

### 🏠 首页卡片布局

- **主播信息卡片** — 头像 + 用户名 + 直播状态指示灯 + 录制控制
- **录制控制** — 录制中显示"停止"+"取消"双按钮（红底），支持确认取消
- **置顶功能** — 点击 📌 图标置顶主播，绿色边框高亮
- **一键录制/结束所有置顶** — AppBar 顶部快捷按钮，批量启动/停止所有置顶直播的录制
- **AppBar 录制计数** — 顶部栏实时显示当前录制数 (● N / 20)

### ⏱️ 录制实时显示

- **录制时长** — 实时显示已录制时间（时:分:秒）
- **文件大小** — 每 5 秒轮询一次，实时显示文件大小
- **停滞检测** — 60 秒未写入数据自动预警，90 秒自动结束（应对服务器限流）
- **错误日志面板** — 录制出错时显示可点击查看的红色日志区域
- **重连状态提示** — 断线重连时显示"重连中(N/3)"

### 🔍 搜索与收藏

- **多平台搜索** — 搜索 Bilibili/抖音/斗鱼/虎牙/猫耳FM 直播间
- **猫耳FM 房间号搜索** — 支持输入房间号直接定位直播间（猫耳无公开搜索 API）
- **抖音 X-Bogus 签名** — 修复了原库缺失的签名算法，搜索正常可用
- **即时收藏反馈** — 点击收藏后心形图标立刻变红
- **收藏分组管理** — 收藏列表区分直播中/未开播，支持置顶
- **数据导入导出** — 兼容 Bililive 格式的 JSON 关注数据导入导出

### 🎬 录音文件管理

- **录音文件浏览** — 独立文件浏览器页面，按主播文件夹分组展示
- **内置音频播放器** — 支持播放、暂停、快进、快退、Seek 进度条
- **文件编辑** — 支持重命名、删除、批量删除操作
- **音频裁剪** — 针筒滑块 UI，支持 FFmpeg 裁剪录音片段

### 🔧 TS 解包工具

- **TS → M4A 一键解包** — 录制时自动解包（纯 remux，不重编码），也支持手动解包
- **批量多选解包** — 跨文件夹多选 TS 文件，一次处理多个
- **按主播分组** — TS 文件按主播名分组展示，清晰明了
- **中断文件检测** — App 启动时自动扫描异常中断的 TS 文件并标记 `_interrupted`

### ⚙️ 设置与权限

- **主题切换** — Material3 light/dark 模式切换，支持动态色 + 自定义强调色
- **音频存储路径** — 自定义录音文件保存目录（选择器 + 手动输入）
- **按主播名分文件夹** — 自动按主播名创建子文件夹存储
- **音频输出格式** — 支持 M4A / MP3 / FLAC / WAV / OGG 可选
- **调试日志页面** — 实时日志查看、保存、清空
- **存储权限** — Android 11+ 自动请求"管理所有文件"权限
- **Android 13+ 通知权限** — 前台服务启动前确保通知权限已授予

### 🚀 性能优化

- **快速启动** — 权限请求异步非阻塞，直播状态在渲染后检测
- **响应式录制状态** — Obx 订阅 `activeSessions`，录制开始/停止即时刷新
- **session 自动清理** — `onFinished` 回调 + `cleanupStaleSessions()` 双重保障，避免计数只增不减
- **顺序批量启动** — 一键录制使用 `for...await` 逐路启动，避免网络突发和 CPU 尖峰
- **零编译警告** — `flutter analyze` 保持零 error/warning
- **减少 FFmpeg 日志开销** — 录制期间不实时回调日志到 Dart 层，降低跨语言调用
- **降低文件轮询频率** — 文件大小从每秒轮询改为每 5 秒，减少 80% 系统调用
- **重试退避延迟** — 断线重连延迟递增 (2s/4s/6s)，降低耗电
- **唤醒锁引用计数** — 多个录制共享一个唤醒锁，避免重复申请/释放

## 初期主要功能清单

- [x] 仅做录播（音频）使用，移除观看直播间功能
- [x] 并行录播，使用 FFmpeg 同时录制多个直播间
- [x] 最多 20 路并行录制
- [x] 仅提供搜索与收藏，移除首页推荐
- [x] 每个直播间卡片显示可收起的 Debug 日志
- [x] 显示录播中的状态（时长、文件大小）
- [x] 刷新直播间状态功能（含进度百分比）
- [x] 断线自动拼接/重连（最多 3 次）
- [x] 保证后台运行
- [x] Android 前台服务保活（熄屏不中断）
- [x] Android 13+ 通知权限 + 前台服务修复
- [x] 录制性能优化（日志裁剪、轮询降频、重试退避）
- [x] 修复网络中断后无法重新录制 bug
- [x] 简化报错提示
- [x] 按主播名自动创建文件夹保存
- [x] 分组筛选（直播中/未开播/全部）
- [x] 置顶收藏直播间（绿色边框高亮）
- [x] 录制完成提示（文件已保存）
- [x] 录制时实时显示时长 + 文件大小
- [x] 停止/取消录制确认对话框
- [x] 搜索页心形收藏 + 即时变红
- [x] TS 片段存储 → 一键解包为 M4A
- [x] 批量多选 TS 文件解包
- [x] 文件浏览页面（主播文件夹分组）
- [x] 内置音频播放器（播放/暂停/Seek/快进快退）
- [x] 音频裁剪功能（针筒滑块 + FFmpeg 裁剪）
- [x] 录制文件重命名、删除、批量删除
- [x] 异常中断 TS 文件自动检测标记
- [x] 抖音 X-Bogus 签名修复
- [x] 猫耳FM 房间号搜索 + 状态检测
- [x] 音频输出格式设置（M4A/MP3/FLAC/WAV/OGG）
- [x] 设置页防溢出、主题切换即时生效
- [x] 动态色 + 自定义强调色
- [x] 一键录制/结束所有置顶直播
- [x] AppBar 实时录制计数
- [x] session 自动清理机制（onFinished + cleanupStaleSessions）
- [x] 录制停滞检测（60s 预警 / 90s 自动结束）
- [x] 顺序批量启动（避免高并发网络突发）
- [x] 关注数据导入导出（兼容 Bililive 格式）
- [x] Android 管理所有文件权限申请
- [x] App 图标更新（flutter_launcher_icons）
- [x] 快速启动、非阻塞权限请求

## 项目结构

```
simple_recorder/
├── lib/
│   ├── main.dart                         # 入口，初始化 Hive/GetX/Permissions/ForegroundService
│   ├── app/
│   │   ├── app_style.dart                # Material3 light/dark 主题 + 动态色 + 强调色
│   │   ├── constant.dart                 # 站点 ID 常量 + 事件总线 key + 音频格式定义
│   │   ├── log.dart                      # 日志工具（环状缓冲区）
│   │   ├── sites.dart                    # 多平台站点注册表（5 平台）
│   │   ├── sites_fixed.dart              # FixedDouyinSite (X-Bogus) + MaoerfmSite
│   │   ├── event_bus.dart                # 跨模块事件总线 (StreamController)
│   │   ├── base_controller.dart          # 基础 GetX Controller 模板
│   │   └── controller/
│   │       └── app_settings_controller.dart  # 全局设置 (path, pin, theme, format)
│   ├── models/db/
│   │   ├── follow_user.dart              # 收藏用户模型 (Hive)
│   │   ├── follow_user.g.dart            # Hive adapter
│   │   ├── recording_task.dart           # 录制任务模型
│   │   └── recording_task.g.dart         # Hive adapter
│   ├── services/
│   │   ├── db_service.dart               # Hive CRUD
│   │   ├── local_storage_service.dart    # Hive settings box
│   │   ├── recording_service.dart        # RecordingSession: FFmpeg 录音核心
│   │   │                                    # - 唤醒锁/前台服务引用计数
│   │   │                                    # - 自动 TS→M4A 解包
│   │   │                                    # - 重试退避 2s/4s/6s
│   │   │                                    # - onFinished 自动清理
│   │   │                                    # - 停滞检测 (60s/90s)
│   │   ├── recording_manager.dart        # 并行录制管理 (RxList) + 20路并发
│   │   │                                    # - cleanupStaleSessions()
│   │   │                                    # - onFinished 回调绑定
│   │   └── follow_export_service.dart    # 关注数据 JSON 导入/导出
│   ├── modules/
│   │   ├── home/                         # 首页：收藏列表 + 录制控制 + 筛选栏
│   │   │                                    # - AppBar: 录制计数 + 一键录制/结束 + 刷新
│   │   ├── search/                       # 多平台搜索（心形收藏即时反馈）
│   │   ├── settings/                     # 设置页（主题/存储/格式/数据/日志）
│   │   │   ├── settings_page.dart
│   │   │   ├── appstyle_setting_page.dart
│   │   │   ├── audio_settings_page.dart
│   │   │   └── audio_format_settings_page.dart
│   │   ├── recordings/                   # 录音文件浏览 + 音频播放器 + 裁剪
│   │   │   ├── recordings_controller.dart
│   │   │   ├── recordings_page.dart
│   │   │   └── audio_player_sheet.dart
│   │   ├── ts_unpack/                    # TS 解包工具（批量多选 + 进度）
│   │   │   ├── ts_unpack_controller.dart
│   │   │   ├── ts_unpack_page.dart
│   │   │   └── ts_unpack_service.dart
│   │   └── debug_log/                    # 调试日志页面（保存/清空）
│   ├── routes/
│   │   ├── app_pages.dart                # GetPage 路由表（8 个路由）
│   │   └── route_path.dart               # 路由路径常量
│   └── widgets/
│       ├── settings/                     # 设置页可复用组件 (card/switch/action/menu/number)
│       └── status/                       # 状态占位组件 (loading/empty/error)
├── android/app/src/main/kotlin/.../MainActivity.kt  # MethodChannel (openFolder)
└── README.md
```

## 路由一览

| 路径 | 页面 | 说明 |
|---|---|---|
| `/` | HomePage | 首页：收藏列表 + 录制控制 |
| `/search` | SearchPage | 多平台搜索 |
| `/settings` | SettingsPage | 主设置 |
| `/settings/appstyle` | AppstyleSettingPage | 外观设置（主题/动态色/强调色） |
| `/settings/audio` | AudioSettingsPage | 音频存储路径 |
| `/settings/audio_format` | AudioFormatSettingsPage | 音频输出格式 |
| `/debug_log` | DebugLogPage | 调试日志 |
| `/ts_unpack` | TsUnpackPage | TS 解包工具 |
| `/recordings` | RecordingsPage | 录音文件浏览 |

## 开始使用

### 环境要求

- Flutter SDK >= 3.11.5
- Dart SDK >= 3.11.5

### 构建运行

```bash
# 获取依赖
flutter pub get

# 生成 Hive 适配器
dart run build_runner build --delete-conflicting-outputs

# 运行
flutter run

# 静态分析
flutter analyze
```

### 平台支持

| 平台 | 支持状态 |
|------|---------|
| Android | ✅ (主要目标平台) |
| iOS | ⚠️ 理论上支持，未充分测试 |
| Linux | ⚠️ 理论上支持，未充分测试 |
| macOS | ⚠️ 理论上支持，未充分测试 |
| Windows | ⚠️ 理论上支持，未充分测试 |

> 注：前台服务保活、启动图标为 Android 专用能力，其他平台无对应功能。

## 依赖的核心库

- `simple_live_core` — 源自 [dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)，本地 path 依赖
- `ffmpeg_kit_flutter_new_https_gpl` — 基于 FFmpeg 的音频录制与格式转换
- `flutter_background_service` — Android 前台服务保活
- `hive` — 本地数据持久化
- `get` — 状态管理与路由
- `permission_handler` — 运行时权限管理
- `wakelock_plus` — 屏幕常亮 / CPU 休眠控制
- `flutter_local_notifications` — 前台服务通知渠道创建（Android 13+ 兼容）

## 架构要点

### Session 生命周期管理

```
RecordingManager 管理所有活跃录制会话:

startRecording(session)
  ├─ activeSessions.add(session)
  ├─ 绑定 session.onFinished → 自动移除
  ├─ session.start()
  └─ start 失败 → 自动清理

session 结束路径:
  ├─ 用户点停止 → stop() → _onFinished() → onFinished → 从列表移除 ✅
  ├─ 用户点取消 → cancel() → _onFinished() → onFinished → 从列表移除 ✅
  ├─ 断流/重试耗尽 → _onFinished() → onFinished → 从列表移除 ✅
  └─ 停滞检测 (90s) → _onFinished() → onFinished → 从列表移除 ✅

checkAllLiveStatus() → cleanupStaleSessions() → 清扫残留僵尸 session
```

### 停滞检测

当录制超过 60 秒文件仍为 0 字节（服务器限流），设置错误提示；超过 90 秒自动结束释放资源。

### 唤醒锁与前台服务

多个录制共享引用计数，仅首个录制获取、末个录制释放，避免重复申请/释放导致的系统开销。

## UI 约定

本项目在卡片布局中有一套 UI 约束，详见 `AGENTS.md`：

- **紧凑布局** — 在受限空间中用 `GestureDetector` + `SizedBox` 替代 `PopupMenuButton`、`IconButton` 等
- **响应式模式** — 卡片状态通过 `Obx(() { final _ = RecordingManager.instance.activeSessions.length; })` 触发重绘
- **防溢出清单** — 先计算可用宽度，列出固定元素，`ConstrainedBox` 限制长文本

## 已知限制

### 并发录制数受限于平台 CDN 限流

虽然 App 支持最高 **20 路** 并行录制，但在实际使用中，受限于各直播平台 CDN 的并发连接限制（通常**单个 IP 约 10 路左右**），超出限制后新增的录制会话会陷入以下状态：

```
FFmpeg 启动 → 连接服务器 ✅（TCP 握手成功）
          → 服务器限流，不发数据
          → 读超时 → -reconnect 自动重连
          → 仍不发数据 → 无限循环
          → 文件始终 0 字节
          → 停滞检测 90 秒后自动结束
```

### 表现特征

| 现象 | 原因 |
|---|---|
| 第 11 路开始显示 "0 B" 文件大小 | 服务器接受了连接但拒绝发送数据 |
| 时长在走但文件一直是 0B | FFmpeg 被 -reconnect 拖入无限重连 |
| 约 90 秒后该路自动消失 | 停滞检测触发，自动清理 |
| 前 10 路不受影响，正常录制 | 未超出 CDN 连接额度 |

### 解决方案

| 方案 | 做法 | 效果 |
|---|---|---|
| **推荐：降上限** | 将 `RecordingManager.maxConcurrent` 改为 10 | 稳定录制，永不触发限流 |
| **保留 20 + 停滞自愈** | 维持现状，超出部分 90s 后自动清理 | 偶尔能抢到 12+ 路，但不可靠 |
| **代理/IP 轮换** | 通过多个网络出口分流请求 | 可突破单 IP 限制，但实现复杂 |
| **去除 -reconnect 参数** | 让 FFmpeg 首次超时就退出，靠 Dart 侧重试 | 更快释放超限连接，但网络闪断时恢复稍慢 |

> 这不是 App 的 bug，而是直播平台 CDN 的基础设施限制。所有同类工具都面临同样的瓶颈。

## 免责声明

1. 本工具仅用于个人学习、研究和合法用途
2. **禁止将录播文件分发至互联网或用于商业用途**
3. 请尊重主播及平台的知识产权
4. 使用者需自行承担相关法律责任

## 开源协议

本项目基于 **GNU General Public License v3.0 (GPLv3)** 开源。

```
Simple Recorder — 多平台直播音频录制工具
Copyright (C) 2025-2026  Simple Recorder contributors

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
```

本项目参考了以下开源项目：
- [Simple Live](https://github.com/xiaoyaocz/dart_simple_live) — GPLv3
- [Bililive](https://github.com/BoooSAMA/bililive) — GPLv3
