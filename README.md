# Simple Recorder

> **多平台直播音频录制工具** — 基于 Flutter 构建，支持 Bilibili / 抖音 / 斗鱼 / 虎牙等多平台直播间音频录制。
>
> **录播功能仅限自用，禁止将录播文件分发至网上。**

## 项目背景

本项目结合了两个开源项目的核心能力：

- **[Simple Live (dart_simple_live)](https://github.com/xiaoyaocz/dart_simple_live)** — 提供多平台直播搜索与房间信息获取能力
- **[Bililive](https://github.com/BoooSAMA/bililive)** — 提供基于 FFmpeg 的直播间音频录制核心功能

初期目标：取 Simple Live 的多平台访问功能，取 Bililive 的录音功能，打造一个纯粹的多平台直播音频录制工具。

## 功能特性

- **多平台搜索** — 支持 Bilibili、抖音、斗鱼、虎牙四大平台直播间搜索
- **纯音频录制** — 仅录制音频，移除视频直播观看功能
- **并行录制** — 基于 FFmpeg 同时录制多个直播间，互不干扰
- **收藏管理** — 收藏常用直播间，随时查看直播状态
- **直播状态监测** — 自动检测已收藏主播的开播状态
- **断线自动重连** — 录制中断自动重试（最多3次），保障录制完整性
- **按主播名分类** — 自动按主播名创建文件夹存储音频文件
- **Debug 日志** — 每个录制卡片显示可收起的调试日志
- **后台运行** — 支持后台持续录制
- **简化报错** — 精简友好的错误提示

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
- [x] README 中声明仅限自用，禁止分发

## 项目结构

```
simple_recorder/
├── lib/
│   ├── main.dart                         # 入口
│   ├── app/
│   │   ├── app_style.dart                # 主题样式
│   │   ├── constant.dart                 # 常量定义
│   │   ├── log.dart                      # 日志工具
│   │   ├── sites.dart                    # 多平台站点管理
│   │   └── controller/
│   │       └── app_settings_controller.dart
│   ├── models/
│   │   └── db/
│   │       ├── follow_user.dart          # 收藏用户模型
│   │       └── recording_task.dart       # 录制任务模型
│   ├── services/
│   │   ├── db_service.dart               # 数据库服务
│   │   ├── local_storage_service.dart    # 本地存储
│   │   ├── recording_service.dart        # 单房间录制服务
│   │   └── recording_manager.dart        # 并行录制管理器
│   ├── modules/
│   │   ├── home/                         # 首页（录制列表）
│   │   ├── search/                       # 多平台搜索
│   │   └── settings/                     # 设置页
│   ├── routes/
│   │   ├── app_pages.dart
│   │   └── route_path.dart
│   └── widgets/
├── project_init_features.md              # 项目初始设计文档
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
