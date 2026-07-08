<p align="center">
  <img src="logo.png" alt="Simple Recorder" width="120"/>
</p>

<p align="center">
  English · <a href="README.md"><strong>中文</strong></a>
</p>

# Simple Recorder

> **Multi-platform live stream audio recorder** — Built with Flutter, supporting Bilibili / Douyin (TikTok China) / Douyu / Huya / MaoerFM for live room audio recording.
>
> **For personal use only. Do NOT distribute recorded content online.**

## Project Background

This project combines the core capabilities of two open-source projects:

- **[Simple Live (dart_simple_live)](https://github.com/xiaoyaocz/dart_simple_live)** — Provides multi-platform live search and room information retrieval
- **[Bililive](https://github.com/BoooSAMA/bililive)** — Provides FFmpeg-based live room audio recording core functionality

## Quick Start

### Step 1: First-time Setup

```bash
# 1. Clone the project
git clone https://github.com/your/simple_recorder.git
cd simple_recorder

# 2. Install dependencies
flutter pub get

# 3. Generate Hive adapters
dart run build_runner build --delete-conflicting-outputs

# 4. Run
flutter run
```

> On Android, the app will automatically request "Manage all files" permission (Android 11+) and "Notification" permission (Android 13+) on first launch. Grant these for proper foreground recording.

### Step 2: Set Storage Path

1. Launch the app → tap the **gear icon** in the bottom-right to enter Settings
2. Tap **Audio storage path** → select or enter your preferred recording directory
3. It's recommended to enable **Organize by streamer name** — recordings will be auto-sorted into folders

### Step 3: Search and Follow Streamers

1. Tap the **🔍 search icon** in the top bar to enter the Search page
2. Select a platform (Bilibili / Douyin / Douyu / Huya / MaoerFM)
3. Enter the streamer's name (MaoerFM requires a room ID number) → Search
4. In the results list, tap the **♡ heart icon** to follow → it turns red instantly, and the streamer appears on the Home page

> You can also unfollow streamers from this page.

### Step 4: Check Live Status

1. Return to the Home page and tap the **🔄 refresh button** in the top-left (animated progress indicator)
2. The system checks the live status of all followed streamers:
   - 🟢 **Live** — Green highlight, displayed at the top of the list
   - ⚫ **Offline** — Grayed out, grouped below
3. Use the filter bar at the top to switch views: **Live** / **Offline** / **All**

### Step 5: Pin Favorite Streamers

1. Find your frequently-watched streamer on the card list
2. Tap the **📌 pin button** in the bottom-right corner
3. Pinned streamers' cards show a **green border** and always stay at the top of the list

> Pinning also syncs with live status polling (auto-checks every 3 minutes in the background) and sends notifications when they go live.

### Step 6: Start Recording

#### Method A: Single Recording

Tap the **🎙️ Record button** on a streamer's card → the card turns red with live display:
- **Duration** — Elapsed recording time (HH:MM:SS)
- **File size** — Amount of data recorded
- **Status** — Recording normally / Reconnecting (N/3) / Error log

#### Method B: One-Click Batch Record (Recommended)

When multiple pinned streamers are live simultaneously, the top AppBar shows a **● Record All** button:

1. The button shows how many are recordable → tap to start
2. Sessions start **one by one** (not simultaneously), avoiding network bursts
3. A progress circle updates in real-time. When complete, a summary popup shows: `Started: 4 | Skipped/Failed: 0`

> Only live streamers who aren't already being recorded will be started; already-recording sessions are skipped automatically.

### Step 7: Manage In-Progress Recordings

- **Stop** — Tap the red **Stop button** → saves the current TS file and auto-unpacks to M4A
- **Cancel (discard)** — Tap the **Cancel button** → confirmation dialog → deletes the recorded TS file
- **Stop All Pinned** — When pinned recordings are active, the AppBar shows a **■ Stop All button** → ends all at once

> Switching the app to the background during recording is safe. Android foreground service keeps it alive.

### Step 8: View and Manage Recordings

1. Tap **⋮ Menu** in the AppBar → **Browse Recordings**
2. Files are grouped by **streamer folder** for easy navigation
3. Tap a file to **preview playback** (built-in player)
4. Supports **rename**, **delete**, and **batch delete**

#### Audio Trimming

In the player interface, use the **syringe-style sliders** to precisely trim audio clips:

1. Drag the sliders to select the start and end positions
2. Tap Trim → FFmpeg automatically generates the trimmed file
3. The original file is preserved

### Step 9: TS Unpacking (Error Recovery)

Normally recorded files are **auto-unpacked** to M4A when stopped. If you see leftover `.ts` files:

1. AppBar → **⋮ Menu** → **TS Unpack**
2. Files are grouped by streamer name, with **cross-folder multi-select** support
3. Check files and tap Batch Unpack → progress bar follows → original TS files are deleted on completion
4. Files marked with `_interrupted` are abnormally terminated recordings — they can also be unpacked

> The app automatically scans and marks interrupted TS files on each startup. No manual action needed.

### Step 10: Advanced Settings

| Setting | Location | Description |
|---|---|---|
| Theme / Accent color | Settings → Appearance | Light/dark + dynamic color + custom accent |
| Audio format | Settings → Audio format | M4A / MP3 / FLAC / WAV / OGG |
| Export follows | Settings → Data | JSON format, Bililive-compatible |
| Debug log | Settings → Debug log | View, save, and clear recording logs in real-time |

## Features

### 🎙️ Recording Core

- **Multi-platform** — Bilibili, Douyin, Douyu, Huya, MaoerFM
- **Audio-only recording** — FFmpeg `c:a copy` (no re-encoding), saves storage space
- **Parallel recording** — Record up to 20 live rooms simultaneously without interference
- **Auto-reconnect** — Automatic retry on disconnection (up to 3 times, with 2s/4s/6s backoff)
- **FFmpeg TS encapsulation** — Temporarily stored as TS segments, auto-merged to M4A on stop
- **Background recording** — Continues recording when the app is in the background
- **Foreground service** — Android foreground service notification prevents the system from killing the process
- **Shared wakelock** — Multiple recordings share one wakelock via reference counting, saving power

### 📡 Live Status Monitoring

- **Batch concurrent checks** — 5 rooms queried in parallel per batch, avoiding UI blocking
- **Progressive UI updates** — Each result syncs immediately instead of waiting for the full batch
- **Real-time progress** — Refresh button with built-in circular progress and percentage text
- **Filter bar** — Live / Offline / All three views with count badges

### 🏠 Home Card Layout

- **Streamer info cards** — Avatar + username + live status indicator + recording controls
- **Recording controls** — "Stop" + "Cancel" dual buttons (red background), with cancel confirmation
- **Pin to top** — 📌 icon to pin streamers, green border highlight
- **One-click record/stop all pinned** — AppBar quick buttons for batch start/stop
- **AppBar recording count** — Real-time recording count display (● N / 20)

### ⏱️ Real-time Recording Display

- **Duration** — Real-time elapsed time (HH:MM:SS)
- **File size** — Polled every 5 seconds for live file size display
- **Stall detection** — Warning at 60 seconds of no data, auto-stop at 90 seconds (handles CDN rate limiting)
- **Error log panel** — Clickable red error log area on recording failure
- **Reconnect status** — Shows "Reconnecting (N/3)" during reconnection

### 🔍 Search & Following

- **Multi-platform search** — Search Bilibili/Douyin/Douyu/Huya/MaoerFM rooms
- **MaoerFM room ID search** — Enter room number directly (MaoerFM has no public search API)
- **Douyin X-Bogus signature** — Fixed the original library's missing signature algorithm for working search
- **Instant follow feedback** — Heart icon turns red immediately on follow
- **Follow grouping** — Separate live/offline lists with pin support
- **Data import/export** — Bililive-compatible JSON format for follow data

### 🎬 Recording File Management

- **File browser** — Dedicated file browser page, grouped by streamer folder
- **Built-in audio player** — Play, pause, skip forward/back, seek progress bar
- **File editing** — Rename, delete, batch delete
- **Audio trimming** — Syringe-style slider UI with FFmpeg-based clip processing

### 🔧 TS Unpack Tool

- **TS → M4A one-click unpack** — Auto-unpacks on recording stop (pure remux, no re-encoding), also supports manual unpack
- **Batch multi-select** — Cross-folder multi-select for batch processing
- **Group by streamer** — TS files displayed grouped by streamer name
- **Interrupted file detection** — Automatically scans and marks abnormally terminated TS files with `_interrupted` on app startup

### ⚙️ Settings & Permissions

- **Theme switching** — Material3 light/dark mode, dynamic color + custom accent color
- **Audio storage path** — Custom recording directory (picker + manual input)
- **Organize by streamer name** — Auto-creates sub-folders per streamer
- **Audio output format** — M4A / MP3 / FLAC / WAV / OGG selectable
- **Debug log page** — Real-time log viewing, saving, and clearing
- **Storage permission** — Android 11+ "Manage all files" auto-request
- **Android 13+ notification permission** — Ensures notification permission is granted before foreground service start

### 🚀 Performance Optimizations

- **Fast startup** — Async non-blocking permission requests, live status checked after rendering
- **Reactive recording state** — Obx subscription on `activeSessions`, instant refresh on start/stop
- **Auto session cleanup** — `onFinished` callback + `cleanupStaleSessions()` double guarantee against count inflation
- **Sequential batch start** — One-click record uses `for...await` to start one-by-one, avoiding network bursts and CPU spikes
- **Zero compilation warnings** — `flutter analyze` maintains zero errors/warnings
- **Reduced FFmpeg log overhead** — No real-time log callbacks to Dart layer during recording
- **Lower file polling frequency** — File size polling reduced from 1s to 5s, 80% fewer syscalls
- **Retry backoff** — Incremental reconnect delay (2s/4s/6s), reduced power consumption
- **Wakelock reference counting** — Multiple recordings share a single wakelock, avoiding duplicate acquire/release

## Feature Checklist

- [x] Audio-only recording, removed live video playback
- [x] Parallel recording with FFmpeg across multiple rooms
- [x] Up to 20 concurrent recordings
- [x] Search & follow only, no homepage recommendations
- [x] Collapsible debug log per room card
- [x] Live recording status display (duration, file size)
- [x] Live status refresh with progress percentage
- [x] Auto-reconnect on disconnection (up to 3 retries)
- [x] Background recording support
- [x] Android foreground service (screen-off survival)
- [x] Android 13+ notification permission + foreground service fix
- [x] Performance optimizations (log trimming, polling reduction, retry backoff)
- [x] Fixed "cannot re-record after network drop" bug
- [x] Simplified error messages
- [x] Auto-create folders by streamer name
- [x] Group filtering (Live / Offline / All)
- [x] Pin streamers to top (green border highlight)
- [x] Recording complete notification
- [x] Real-time duration + file size display
- [x] Stop/Cancel recording confirmation dialog
- [x] Heart icon follow with instant red feedback
- [x] TS segment storage → one-click M4A unpack
- [x] Batch multi-select TS file unpacking
- [x] File browser page (grouped by streamer folder)
- [x] Built-in audio player (play/pause/seek/skip)
- [x] Audio trimming (syringe slider + FFmpeg)
- [x] Recording file rename, delete, batch delete
- [x] Auto-detect and mark interrupted TS files
- [x] Douyin X-Bogus signature fix
- [x] MaoerFM room ID search + status detection
- [x] Audio output format settings (M4A/MP3/FLAC/WAV/OGG)
- [x] Settings page overflow prevention, instant theme switching
- [x] Dynamic color + custom accent color
- [x] One-click record/stop all pinned streamers
- [x] AppBar real-time recording count
- [x] Auto session cleanup (onFinished + cleanupStaleSessions)
- [x] Recording stall detection (60s warning / 90s auto-stop)
- [x] Sequential batch start (avoids concurrent network burst)
- [x] Follow data import/export (Bililive-compatible)
- [x] Android "Manage all files" permission request
- [x] App icon update (flutter_launcher_icons)
- [x] Fast startup, non-blocking permission requests

## Project Structure

```
simple_recorder/
├── lib/
│   ├── main.dart                         # Entry point: Hive/GetX/Permissions/ForegroundService init
│   ├── app/
│   │   ├── app_style.dart                # Material3 light/dark theme + dynamic color + accent
│   │   ├── constant.dart                 # Platform ID constants + event bus keys + audio format defs
│   │   ├── log.dart                      # Logger (ring buffer)
│   │   ├── sites.dart                    # Multi-platform site registry (5 platforms)
│   │   ├── sites_fixed.dart              # FixedDouyinSite (X-Bogus) + MaoerfmSite
│   │   ├── event_bus.dart                # Cross-module event bus (StreamController)
│   │   ├── base_controller.dart          # Base GetX Controller template
│   │   └── controller/
│   │       └── app_settings_controller.dart  # Global settings (path, pin, theme, format)
│   ├── models/db/
│   │   ├── follow_user.dart              # Followed user model (Hive)
│   │   ├── follow_user.g.dart            # Hive adapter
│   │   ├── recording_task.dart           # Recording task model
│   │   └── recording_task.g.dart         # Hive adapter
│   ├── services/
│   │   ├── db_service.dart               # Hive CRUD
│   │   ├── local_storage_service.dart    # Hive settings box
│   │   ├── recording_service.dart        # RecordingSession: FFmpeg recording core
│   │   │                                    # - Wakelock/foreground service ref counting
│   │   │                                    # - Auto TS→M4A unpack
│   │   │                                    # - Retry backoff 2s/4s/6s
│   │   │                                    # - onFinished auto cleanup
│   │   │                                    # - Stall detection (60s/90s)
│   │   ├── recording_manager.dart        # Parallel recording manager (RxList) + 20-way concurrency
│   │   │                                    # - cleanupStaleSessions()
│   │   │                                    # - onFinished callback binding
│   │   └── follow_export_service.dart    # Follow data JSON import/export
│   ├── modules/
│   │   ├── home/                         # Home: follow list + recording controls + filter bar
│   │   │                                    # - AppBar: recording count + one-click record/stop + refresh
│   │   ├── search/                       # Multi-platform search (instant heart follow)
│   │   ├── settings/                     # Settings (theme/storage/format/data/log)
│   │   │   ├── settings_page.dart
│   │   │   ├── appstyle_setting_page.dart
│   │   │   ├── audio_settings_page.dart
│   │   │   └── audio_format_settings_page.dart
│   │   ├── recordings/                   # Recording file browser + audio player + trimmer
│   │   │   ├── recordings_controller.dart
│   │   │   ├── recordings_page.dart
│   │   │   └── audio_player_sheet.dart
│   │   ├── ts_unpack/                    # TS unpack tool (batch multi-select + progress)
│   │   │   ├── ts_unpack_controller.dart
│   │   │   ├── ts_unpack_page.dart
│   │   │   └── ts_unpack_service.dart
│   │   └── debug_log/                    # Debug log page (save/clear)
│   ├── routes/
│   │   ├── app_pages.dart                # GetPage route table (9 routes)
│   │   └── route_path.dart               # Route path constants
│   └── widgets/
│       ├── settings/                     # Reusable settings components (card/switch/action/menu/number)
│       └── status/                       # State placeholder components (loading/empty/error)
├── android/app/src/main/kotlin/.../MainActivity.kt  # MethodChannel (openFolder)
└── README.md
```

## Routes

| Path | Page | Description |
|---|---|---|
| `/` | HomePage | Home: follow list + recording controls |
| `/search` | SearchPage | Multi-platform search |
| `/settings` | SettingsPage | Main settings |
| `/settings/appstyle` | AppstyleSettingPage | Appearance (theme/dynamic color/accent) |
| `/settings/audio` | AudioSettingsPage | Audio storage path |
| `/settings/audio_format` | AudioFormatSettingsPage | Audio output format |
| `/debug_log` | DebugLogPage | Debug log |
| `/ts_unpack` | TsUnpackPage | TS unpack tool |
| `/recordings` | RecordingsPage | Recording file browser |

## Getting Started

### Requirements

- Flutter SDK >= 3.11.5
- Dart SDK >= 3.11.5

### Build & Run

```bash
# Install dependencies
flutter pub get

# Generate Hive adapters
dart run build_runner build --delete-conflicting-outputs

# Run
flutter run

# Static analysis
flutter analyze
```

### Platform Support

| Platform | Status |
|----------|--------|
| Android | ✅ (Primary target) |
| iOS | ⚠️ Theoretically supported, not fully tested |
| Linux | ⚠️ Theoretically supported, not fully tested |
| macOS | ⚠️ Theoretically supported, not fully tested |
| Windows | ⚠️ Theoretically supported, not fully tested |

> Note: Foreground service and launcher icons are Android-specific capabilities.

## Core Dependencies

- `simple_live_core` — From [dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live), local path dependency
- `ffmpeg_kit_flutter_new_https_gpl` — FFmpeg-based audio recording and format conversion
- `flutter_background_service` — Android foreground service keepalive
- `hive` — Local data persistence
- `get` — State management and routing
- `permission_handler` — Runtime permission management
- `wakelock_plus` — Screen-on / CPU sleep control
- `flutter_local_notifications` — Foreground service notification channel creation (Android 13+ compatibility)

## Architecture Highlights

### Session Lifecycle Management

```
RecordingManager manages all active recording sessions:

startRecording(session)
  ├─ activeSessions.add(session)
  ├─ bind session.onFinished → auto-remove
  ├─ session.start()
  └─ start failed → auto-cleanup

Session termination paths:
  ├─ User stops → stop() → _onFinished() → onFinished → removed from list ✅
  ├─ User cancels → cancel() → _onFinished() → onFinished → removed from list ✅
  ├─ Disconnect/retries exhausted → _onFinished() → onFinished → removed from list ✅
  └─ Stall detection (90s) → _onFinished() → onFinished → removed from list ✅

checkAllLiveStatus() → cleanupStaleSessions() → sweeps remaining zombie sessions
```

### Stall Detection

When a recording exceeds 60 seconds with the file still at 0 bytes (server rate limiting), an error warning is set. After 90 seconds, the session auto-terminates and releases resources.

### Wakelock & Foreground Service

Multiple recordings share reference counts: acquired by the first recording, released by the last. This avoids duplicate acquire/release overhead.

## UI Conventions

This project follows specific UI constraints in card layouts (see `AGENTS.md`):

- **Compact layout** — Use `GestureDetector` + `SizedBox` instead of `PopupMenuButton`, `IconButton` etc. in constrained spaces
- **Reactive pattern** — Card state triggers rebuild via `Obx(() { final _ = RecordingManager.instance.activeSessions.length; })`
- **Overflow prevention** — Calculate available width first, list fixed elements, use `ConstrainedBox` for long text

## Known Limitations

### Concurrent Recording Limited by CDN Rate Limiting

While the app supports up to **20 concurrent** recordings, in practice each platform's CDN imposes a per-IP connection limit (typically **around 10 connections**). Beyond this limit, new recording sessions enter the following state:

```
FFmpeg start → connect to server ✅ (TCP handshake succeeds)
            → server rate-limits, sends no data
            → read timeout → -reconnect auto-reconnect
            → still no data → infinite loop
            → file stays at 0 bytes
            → stall detection ends after 90 seconds
```

### Symptoms

| Symptom | Cause |
|---|---|
| Session #11+ shows "0 B" file size | Server accepted connection but refuses to send data |
| Duration increases but file stays at 0B | FFmpeg trapped in -reconnect infinite loop |
| Session auto-disappears after ~90s | Stall detection triggers cleanup |
| First 10 sessions unaffected | Within CDN connection quota |

### Mitigation

| Approach | Action | Effect |
|---|---|---|
| **Recommended: Lower limit** | Set `RecordingManager.maxConcurrent` to 10 | Stable recording, never hits rate limit |
| **Keep 20 + stall self-heal** | Maintain status quo, excess auto-clean after 90s | May occasionally get 12+, but unreliable |
| **Proxy/IP rotation** | Distribute requests across multiple network egress points | Can bypass single-IP limit, but complex to implement |
| **Remove -reconnect parameter** | Let FFmpeg exit on first timeout, rely on Dart-side retry | Frees up rate-limited connections faster, but network blips recover slightly slower |

> This is not a bug in the app. It is an infrastructure limitation of live streaming platform CDNs. All similar tools face the same bottleneck.

## Disclaimer

1. This tool is for personal learning, research, and lawful use only
2. **Do NOT distribute recorded content on the internet or use it commercially**
3. Please respect the intellectual property rights of streamers and platforms
4. Users assume all related legal responsibilities

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**.

```
Simple Recorder — Multi-platform live stream audio recorder
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

This project references the following open-source projects:
- [Simple Live](https://github.com/xiaoyaocz/dart_simple_live) — GPLv3
- [Bililive](https://github.com/BoooSAMA/bililive) — GPLv3
