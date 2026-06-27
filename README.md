# Simple Recorder

> **多平台直播音频录制工具** — 基于 Flutter 构建，支持 Bilibili / 抖音 / 斗鱼 / 虎牙等多平台直播间音频录制。
>
> **录播功能仅限自用，禁止将录播文件分发至网上。**

## 项目背景

本项目结合了两个开源项目的核心能力：

- **[Simple Live (dart_simple_live)](https://github.com/xiaoyaocz/dart_simple_live)** — 提供多平台直播搜索与房间信息获取能力
- **[Bililive](https://github.com/BoooSAMA/bililive)** — 提供基于 FFmpeg 的直播间音频录制核心功能

## 功能特性

- **多平台搜索** — 支持 Bilibili、抖音、斗鱼、虎牙四大平台直播间搜索
- **纯音频录制** — 仅录制音频，无视频直播观看功能
- **并行录制** — 基于 FFmpeg 同时录制多个直播间，互不干扰
- **双列卡片 UI** — 2 列 Grid 紧凑布局，头像 + 开播状态灯 + 录制控制
- **分组筛选** — 直播中 / 未开播分组展示，支持置顶
- **直播状态监测** — 高并发自动检测（8 路并行），渐进式 UI 更新
- **断线自动重连** — 录制中断自动重试（最多 3 次），保障录制完整性
- **录制进度实时显示** — 毛玻璃底板上显示录制时长（红）和文件大小（白）
- **按主播名分类** — 自动按主播名创建文件夹存储音频文件
- **录制完成详情** — 录制结束后显示文件名、文件大小、保存路径
- **卡片淡入动画** — 列表加载时卡片带微上浮淡入效果
- **涟漪按钮反馈** — 录制/停止/取消按钮带 Material 涟漪动画
- **后台运行** — 支持后台持续录制
- **Debug 日志** — 每个录制卡片显示可收起的调试日志

## 初期主要功能清单

- [x] 仅做录播（音频）使用，移除观看直播间功能
- [x] 并行录播，使用 FFmpeg 同时录制多个直播间
- [x] 仅提供搜索与收藏，移除首页推荐
- [x] 每个直播间卡片显示可收起的 Debug 日志
- [x] 显示录播中的状态（时长、文件大小）
- [x] 刷新重连直播间功能
- [x] 断线自动拼接/重连
- [x] 保证后台运行
- [x] 简化报错提示
- [x] 按主播名自动创建文件夹保存
- [x] 2 列卡片 Grid UI 布局
- [x] 分组筛选（直播中/未开播/全部）
- [x] 置顶收藏直播间
- [x] 录制完成详情提示（文件名、大小、路径）
- [x] 毛玻璃录制进度显示
- [x] 卡片淡入动画 + 按钮涟漪反馈
- [x] 状态加载性能优化（8 路并发、无闪烁更新）
- [x] README 中声明仅限自用，禁止分发

## 项目结构

```
simple_recorder/
├── lib/
│   ├── main.dart                         # 入口
│   ├── app/
│   │   ├── app_style.dart                # Material3 light/dark 主题
│   │   ├── constant.dart                 # 常量定义
│   │   ├── log.dart                      # 日志工具
│   │   ├── sites.dart                    # 多平台站点注册
│   │   ├── event_bus.dart                # 跨模块事件总线
│   │   └── controller/
│   │       └── app_settings_controller.dart  # 全局设置
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
│   │   ├── home/                         # 首页（卡片列表 + 录制控制）
│   │   ├── search/                       # 多平台搜索
│   │   └── settings/                     # 设置页（存储路径/外观/数据）
│   ├── routes/
│   │   ├── app_pages.dart
│   │   └── route_path.dart
│   └── widgets/
│       └── settings/                     # 设置页组件 (card, switch, action)
├── android/app/src/main/kotlin/.../MainActivity.kt  # Android 打开文件夹
├── .sisyphus/
│   └── flutter-overflow-guide.md          # Flutter 溢出调试指南
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
- `hive` — 本地数据持久化
- `get` — 状态管理与路由

## UI 约定

本项目在 2 列 Grid 紧凑布局中有一系列 UI 约定，详见 `AGENTS.md`：

- **禁止 Material 包装组件** — 在紧凑空间中用 `GestureDetector` + `SizedBox` 替代 `PopupMenuButton`、`IconButton` 等
- **GetX 响应式模式** — 卡片状态通过 `Obx(() { final _ = RecordingManager.instance.activeSessions.length; })` 触发
- **防溢出清单** — 先计算可用宽度，列出固定元素，确保剩余空间足够

## 免责声明

1. 本工具仅用于个人学习、研究和合法用途
2. **禁止将录播文件分发至互联网或用于商业用途**
3. 请尊重主播及平台的知识产权
4. 使用者需自行承担相关法律责任

## 开源协议

本项目基于 **GNU General Public License v3.0 (GPLv3)** 开源。

```
Simple Recorder — 多平台直播音频录制工具
Copyright (C) 2025  Simple Recorder contributors

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
