# TS 解包工具 — 设计文档

**Date:** 2026-06-30
**Commit:** 4db158b
**Branch:** main

## 概述

由于录制技术从直接输出 M4A 改为用 TS（MPEG Transport Stream）封装音频流，在异常断联或 App 崩溃时会产生未完成重命名的 `.ts` 文件。本功能提供一个内置解包工具，将 TS 容器中的 AAC 音频流无损失提取为 M4A 文件（remux，`-c:a copy`，不重编码），并内置文件浏览器方便批量操作。

## 涉及文件

| 文件 | 类型 | 说明 |
|---|---|---|
| `lib/modules/ts_unpack/ts_unpack_page.dart` | **新增** | TS 解包工具页面 UI |
| `lib/modules/ts_unpack/ts_unpack_controller.dart` | **新增** | 页面状态管理、文件扫描、批量解包控制 |
| `lib/modules/ts_unpack/ts_unpack_service.dart` | **新增** | FFmpeg 解包执行 + 进度回调 |
| `lib/routes/route_path.dart` | **修改** | 添加解包页面路由常量 |
| `lib/routes/app_pages.dart` | **修改** | 注册解包页面 |
| `lib/modules/home/home_page.dart` | **修改** | 在三点菜单中添加入口 |
| `lib/services/recording_service.dart` | **修改** | 调整重命名逻辑以配合中断检测 |
| `lib/main.dart` | **修改** | 启动时扫描并标记中断文件 |

## 异常中断文件标记

### 现状

- **初始文件名**（line 102）：`{userName}_{YYYY-MM-DD}_{HH-mm-ss}.ts`
- **正常完成重命名**（line 263）：`{userName}_{YYYY-MM-DD}_{HH-mm}_{HH-mm}.ts`
- **异常中断**：保持初始文件名，无从得知是否需要解包

### 修改方案

1. **`recording_service.dart` 调整**：原始文件名中的秒数部分改为 `00` 固定值，使其与完成文件的命名格式对齐（都无秒数），避免命名混淆：

   ```
   // 修改前：主播A_2026-06-30_10-00-00.ts  (含秒数)
   // 修改后：主播A_2026-06-30_10-00.ts       (无秒数)
   ```

   这样新录制文件在命名上统一为两种格式：
   - **初始**：`主播A_2026-06-30_10-00.ts`
   - **完成**：`主播A_2026-06-30_10-00_12-00.ts`

   无法区分的旧文件通过启动扫描标记。

2. **启动扫描（`main.dart`）**：初始化后扫描所有 `.ts` 文件，提取文件名做格式匹配：
   - 匹配 `(name)_(date)_(start)_(end).ts` → 已完成
   - 不匹配上述格式（含旧版含秒数命名）→ **重命名为 `{原文件名}_interrupted.ts`**

3. **中断标记格式**：`主播A_2026-06-30_10-00_interrupted.ts`

## 解包原理

FFmpeg 命令（纯 remux，零质量损失）：

```bash
ffmpeg -y -i input.ts -c:a copy -vn -f ipod output.m4a
```

- `-c:a copy`：音频流直拷，不重编码
- `-vn`：忽略视频流（若有）
- `-f ipod`：输出 M4A 容器（兼容性更好，等同于 `-f mp4`）
- 比重新编码快 10-20 倍，零质量损失
- 解包后同目录下出现同名 `.m4a` 文件，TS 文件保留不动

## 页面设计

### 路由

```
RoutePath.kTsUnpack = "/ts_unpack"
AppPages.routes 注册 TsUnpackPage
```

### 入口

主页 AppBar 三点菜单新增菜单项：

```
PopupMenuItem(value: 'ts_unpack')
  → 图标: Icons.unarchive_outlined
  → 标题: "TS 解包工具"
```

### UI 布局

```
┌─ AppBar: "TS 解包工具" ──────────── 右: [刷新] ─┐
│                                                    │
│  📁 主播A  (3个文件)    [⚠️ 1个中断]  [✅ 2个完成] │
│  ├─ ☐ 主播A_..._10-00_12-00.ts       [✅ 已解包]  │
│  ├─ ☐ 主播A_..._14-00_interrupted.ts  [⚠️ 中断]  │
│  └─ ☐ 主播A_..._09-00_11-00.ts                    │
│                                                    │
│  📁 主播B  (2个文件)                               │
│  ├─ ☑ 主播B_..._20-00_22-30.ts                    │
│  └─ ☑ 主播B_..._18-00_19-30.ts                    │
│                                                    │
│  ─────────────────────────────────────────────     │
│  进度: ████████░░ 80% (4/5)                        │
│                                                    │
│  [全选中断] [全选] [取消选择] [开始解包]           │
└────────────────────────────────────────────────────┘
```

**关键交互：**

1. **分组列表**：按主播名（子文件夹）分组，每组可展开/收起
2. **文件状态标记**：
   - `⚠️ 中断`：文件名含 `_interrupted`，背景微红提示
   - `✅ 已解包`：同目录下存在同名 `.m4a` 文件，自动跳过
3. **多选机制**：每个文件前有 Checkbox，跨文件夹批量选择
4. **底部工具栏**：
   - `全选中断`：一键选中所有含 `_interrupted` 的文件
   - `全选` / `取消选择`
   - `开始解包`：逐个队列处理选择的文件
5. **进度条**：线性进度 + "N/M" 文字，每个文件完成后更新
6. **完成提示**：全部完成后弹出 SmartDialog 汇总（成功数 + 失败数）

### 紧凑适配

本项目遵循紧凑布局原则（见 AGENTS.md），页面中所有按钮使用 `GestureDetector` + `SizedBox` 替代 `IconButton`/`TextButton`，避免溢出。

## 数据流

```
TsUnpackController
├── scanDirectory() → 扫描音频路径 → 分组文件列表 (RxList)
│   ├── groupName: String          (主播名/子文件夹名)
│   ├── files: List<FileItem>      (文件信息列表)
│   └── isExpanded: RxBool         (UI 展开状态)
│
├── FileItem
│   ├── path: String
│   ├── fileName: String
│   ├── isInterrupted: bool        (含 _interrupted)
│   ├── isUnpacked: bool           (同目录同文件名 .m4a 存在)
│   └── isSelected: RxBool         (勾选状态)
│
├── selectedCount → 计算属性 (RxInt)
├── isProcessing → RxBool
├── progress → RxDouble (0.0 ~ 1.0)
├── currentFile → RxString
│
└── startBatchUnpack() → 遍历 selectedFiles
    └── TsUnpackService.unpack(file)
        ├── 执行FFmpeg
        ├── 进度回调 → progress 更新
        └── 返回成功/失败 → 更新 FileItem.isUnpacked
```

## 解包服务

`TsUnpackService` 封装 FFmpeg 执行逻辑：

```dart
class TsUnpackService {
  static Future<UnpackResult> unpack(String tsPath, {void Function(double)? onProgress}) async {
    var m4aPath = tsPath.replaceAll('.ts', '.m4a');
    var args = ['-y', '-i', tsPath, '-c:a', 'copy', '-vn', '-f', 'ipod', m4aPath];
    
    var session = await FFmpegKit.executeWithArgumentsAsync(args, (session) async {
      // 完成回调
    }, (log) {
      // 通过 log 解析进度百分比
      // FFmpeg 进度格式: "size=... time=... bitrate=..."
    });
    
    // 返回结果
  }
}
```

进度通过 FFmpegKit 的日志回调中解析 `time=` 字段与文件总时长对比计算。

## 启动扫描逻辑（main.dart）

在 `DBService` 和 `AppSettingsController` 初始化后执行：

```dart
void _markInterruptedFiles() async {
  var savePath = AppSettingsController.instance.audioSavePath.value;
  if (savePath.isEmpty) return;
  
  var dir = Directory(savePath);
  if (!await dir.exists()) return;
  
  // 递归扫描所有子文件夹中的 .ts 文件
  await for (var entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.ts')) {
      var name = entity.path.split('/').last;
      // 检查是否为"无结束时间"的命名格式
      if (_isInterruptedFormat(name)) {
        var newPath = entity.path.replaceAll('.ts', '_interrupted.ts');
        await entity.rename(newPath);
      }
    }
  }
}
```

`_isInterruptedFormat` 判断逻辑：
- 已完成格式：`{name}_{date}_{start}_{end}.ts`（两个时间段，用 `_` 分隔）
- 已标记中断：`{name}_{date}_{start}_interrupted.ts`
- 属于中断的原始格式：`{name}_{date}_{start}.ts`（仅一个时间段）

## 修改清单

### 新增文件
1. `lib/modules/ts_unpack/ts_unpack_page.dart`
2. `lib/modules/ts_unpack/ts_unpack_controller.dart`
3. `lib/modules/ts_unpack/ts_unpack_service.dart`

### 修改文件
1. `lib/routes/route_path.dart` — 添加 `kTsUnpack` 路由常量
2. `lib/routes/app_pages.dart` — 注册 `TsUnpackPage`
3. `lib/modules/home/home_page.dart` — 三点菜单添加"TS 解包工具"
4. `lib/services/recording_service.dart` — 调整原始文件名格式（去秒数）
5. `lib/main.dart` — 启动时扫描并标记中断文件

## 错误处理

| 场景 | 行为 |
|---|---|
| 音频路径未设置 | 页面显示提示"请先在设置中配置音频存储路径" |
| 目录不存在 | 提示"目录不存在" |
| 没有可解包的文件 | `开始解包` 按钮置灰 |
| FFmpeg 解包失败 | 记录错误日志，继续下一个文件，最终汇总失败列表 |
| 同名 .m4a 已存在 | 跳过不解包，标记为 ✅ 已解包 |
| 文件被占用 | 捕获异常，标记失败 |

## 约束

- 本项目遵循紧凑布局规则（见 AGENTS.md），解包页面所有按钮使用 `GestureDetector` + `SizedBox` 替代 Material 包装组件
- 文件操作使用 `dart:io` 同步/异步 API，避免阻塞 UI
- FFmpeg 使用已有的 `ffmpeg_kit_flutter_new_https_gpl` 依赖
- 文件选择通过 `file_picker` 依赖（已有的）
