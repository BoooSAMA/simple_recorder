# Simple Recorder

> **多平台直播音频录制工具** — 基于 Flutter 构建，支持 Bilibili / 抖音 / 斗鱼 / 虎牙 / 猫耳FM 多平台直播间音频录制。
>
> **录播仅限自用，禁止将录播文件分发至网上。**

## 项目背景

本项目结合了两个开源项目的核心能力：

- **[Simple Live (dart_simple_live)](https://github.com/xiaoyaocz/dart_simple_live)** — 提供多平台直播搜索与房间信息获取能力
- **[Bililive](https://github.com/BoooSAMA/bililive)** — 提供基于 FFmpeg 的直播间音频录制核心功能

## 功能特性

### 🎙️ 录制核心

- **多平台支持** — Bilibili、抖音、斗鱼、虎牙、猫耳FM 五大平台
- **纯音频录制** — 基于 FFmpeg 仅录制音频流 (c:a copy, 不重编码)，节省存储空间
- **并行录制** — 同时录制多个直播间，互不干扰
- **断线自动重连** — 录制中断自动重试（最多 3 次），保障录制完整性
- **FFmpeg TS 格式封装** — 录制时暂存为 TS 片段，停止后自动合成为 M4A 文件
- **后台持续录制** — 支持 app 切到后台后持续录制
- **前台服务保活** — Android 录制时启动前台服务通知，防止系统杀死后台进程，解决熄屏后录制中断问题

### 📡 直播状态监测

- **分批并发检测** — 每批 5 个直播间并行查询，避免阻塞 UI
- **渐进式 UI 更新** — 每完成一个立即同步到列表，无需等全量刷新
- **实时进度反馈** — 刷新按钮内置环形进度 + 百分比文字
- **分组筛选栏** — 直播中 / 未开播 / 全部 三种视图，带数量 badge

### 🔍 搜索与收藏

- **多平台搜索** — 搜索 Bilibili/抖音/斗鱼/虎牙/猫耳FM 直播间
- **猫耳FM 房间号搜索** — 支持输入房间号直接定位直播间
- **即时收藏反馈** — 点击收藏后心形图标立刻变红
- **收藏分组管理** — 收藏列表区分直播中/未开播，支持搜索

### 🏠 首页卡片布局

- **主播信息卡片** — 头像 + 用户名 + 直播状态指示灯 + 录制控制
- **录制控制** — 录制中显示"停止"+"取消"双按钮（红底），支持确认取消
- **置顶功能** — 点击 📌 图标置顶，绿色边框高亮
- **循环列表布局** — 非 Grid，单个卡片垂直排列，每行一个
- **录制完成提示** — 停止录制后 SnackBar 提示"文件已保存"

### ⏱️ 录制实时显示

- **录制时长** — 实时显示已录制时间（时:分:秒）
- **文件大小** — 实时显示已录制文件大小
- **错误日志面板** — 录制出错时显示可点击查看的红色日志区域
- **重连状态提示** — 断线重连时显示"重连中(N/3)"

### 🎬 录音文件管理

- **录音文件浏览** — 独立文件浏览器页面，按主播文件夹分组展示
- **TS → M4A 解包** — 支持将 TS 片段一键解包为 M4A 音频文件
- **批量解包** — 跨文件夹多选 TS 文件，批量解包处理
- **音频播放器** — 内置音频播放器，支持播放、暂停、快进、快退、Seek 进度条
- **文件编辑** — 支持重命名、删除、批量删除操作
- **中断 TS 检测** — App 启动时自动扫描异常中断的 TS 文件并标记

### ⚙️ 设置与权限

- **主题切换** — Material3 light/dark 模式切换
- **音频存储路径** — 自定义录音文件保存目录
- **按主播名分文件夹** — 自动按主播名创建子文件夹存储
- **调试日志页面** — 实时日志查看、保存、清空
- **存储权限** — Android 11+ 自动请求"管理所有文件"权限

### 🚀 性能优化

- **快速启动** — 权限请求异步非阻塞，直播状态在渲染后检测
- **响应式录制状态** — Obx 订阅 `activeSessions`，录制开始/停止即时刷新
- **一致 UI 约束** — `ConstrainedBox` 限制长文本溢出，设置页不崩溃
- **零编译警告** — `flutter analyze` 保持零 error/warning
- **减少 FFmpeg 日志开销** — 录制期间不实时回调日志到 Dart 层，降低跨语言调用
- **降低文件轮询频率** — 文件大小从每秒轮询改为每 5 秒，减少 80% 系统调用
- **重试退避延迟** — 断线重连延迟从固定 2s 改为递增 (2s/4s/6s)，降低耗电

## 初期主要功能清单

- [x] 仅做录播（音频）使用，移除观看直播间功能
- [x] 并行录播，使用 FFmpeg 同时录制多个直播间
- [x] 仅提供搜索与收藏，移除首页推荐
- [x] 每个直播间卡片显示可收起的 Debug 日志
- [x] 显示录播中的状态（时长、文件大小）
- [x] 刷新直播间状态功能（含进度百分比）
- [x] 断线自动拼接/重连（最多 3 次）
- [x] 保证后台运行
- [x] Android 前台服务保活（熄屏不中断）
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
- [x] 录制文件重命名、删除、批量删除
- [x] 异常中断 TS 文件自动检测标记
- [x] 猫耳FM 房间号搜索
- [x] 猫耳FM 直播状态检测与录制
- [x] 设置页防溢出、主题切换即时生效
- [x] Android 管理所有文件权限申请
- [x] App 图标更新（flutter_launcher_icons）
- [x] 快速启动、非阻塞权限请求

## 项目结构

```
simple_recorder/
├── lib/
│   ├── main.dart                         # 入口，初始化 Hive/GetX/Permissions/ForegroundService
│   ├── app/
│   │   ├── app_style.dart                # Material3 light/dark 主题
│   │   ├── constant.dart                 # 常量定义
│   │   ├── log.dart                      # 日志工具
│   │   ├── sites.dart                    # 多平台站点注册表
│   │   ├── event_bus.dart                # 跨模块事件总线
│   │   └── controller/
│   │       └── app_settings_controller.dart  # 全局设置 (path, pin, theme)
│   ├── models/
│   │   └── db/
│   │       ├── follow_user.dart          # 收藏用户模型 (Hive)
│   │       └── recording_task.dart       # 录制任务模型
│   ├── services/
│   │   ├── db_service.dart               # Hive CRUD
│   │   ├── local_storage_service.dart    # Hive settings box
│   │   ├── recording_service.dart        # RecordingSession: FFmpeg 录音核心
│   │   ├── recording_manager.dart        # 并行录制管理 (RxList)
│   │   └── follow_export_service.dart    # 数据导入导出
│   ├── modules/
│   │   ├── home/                         # 首页（卡片列表 + 录制控制 + 筛选栏）
│   │   ├── search/                       # 多平台搜索（心形收藏即时反馈）
│   │   ├── settings/                     # 设置页（存储路径/外观/数据/日志）
│   │   ├── recordings/                   # 录音文件浏览 + 音频播放器
│   │   ├── ts_unpack/                    # TS 解包工具（支持批量多选）
│   │   └── debug_log/                    # 调试日志页面
│   ├── routes/
│   │   ├── app_pages.dart
│   │   └── route_path.dart
│   └── widgets/
│       └── settings/                     # 设置页组件 (card, switch, action)
├── android/app/src/main/.../MainActivity.kt     # Android MethodChannel (openFolder + BackgroundService)
└── README.md
```

## 开始使用

### 环境要求

- Flutter SDK >= 3.10.0
- Dart SDK >= 3.10.0

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
| Android | ✅ |
| iOS | ✅ |
| Linux | ✅ |
| macOS | ✅ |
| Windows | ✅ |

## 依赖的核心库

- `simple_live_core` — 源自 [dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)，提供多平台直播接口
- `ffmpeg_kit_flutter` — 基于 FFmpeg 的音频录制
- `flutter_background_service` — Android 前台服务保活，防止熄屏后录制被系统杀死
- `hive` — 本地数据持久化
- `get` — 状态管理与路由
- `permission_handler` — 运行时权限管理
- `wakelock_plus` — 屏幕常亮 / CPU 休眠控制

## UI 约定

本项目在卡片布局中有一套 UI 约束，详见 `AGENTS.md`：

- **紧凑布局** — 在受限空间中用 `GestureDetector` + `SizedBox` 替代 `PopupMenuButton`、`IconButton` 等
- **响应式模式** — 卡片状态通过 `Obx(() { final _ = RecordingManager.instance.activeSessions.length; })` 触发重绘
- **防溢出清单** — 先计算可用宽度，列出固定元素，`ConstrainedBox` 限制长文本

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
