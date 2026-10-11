# Veil Player v1.0.0 — Initial Public Release

We are proud to present the first stable public release of **Veil Player** (v1.0.0+1), a minimalist, high-performance, AMOLED-optimized Android media player designed around local playback and privacy.

---

## 🎬 What's New in Version 1.0.0

### High-Performance Video Playback
- **MediaKit Engine**: Powered by `media_kit` (libmpv backend) with hardware acceleration (`MediaCodec`) and automatic software decoding fallback.
- **Intuitive Gesture Controls**: Left/right vertical swipe for brightness and volume, horizontal swipe for scrubbing with real-time preview, double-tap 10-second skip with ripple feedback, and long-press 2.0x playback speed preview.
- **Subtitles & Multi-Track Audio**: Embedded audio/subtitle track selection, automatic discovery of external `.srt`, `.vtt`, `.ass`, and `.ssa` subtitle files, and manual audio/subtitle delay synchronization.
- **Picture-in-Picture (PiP)**: Native multitasking with aspect ratio preservation.
- **Aspect Ratio & Display Modes**: Switch between Fit, Stretch, 16:9, 4:3, and Zoom/Crop with orientation and screen-touch locking.
- **Playback Tools**: Sleep timer ('Off', 15m, 30m, 60m, 'End of Video'), Focus Mode (Do Not Disturb integration), and technical media inspector.
- **Fault-Tolerant Playback**: Error recovery HUD with actionable Retry and Skip to Next controls for corrupted or unreadable files.

### Dedicated Music & Audio System
- **Comprehensive Audio Library**: Tracks, Folders, Playlists, and Search tabs.
- **Native Background Audio**: Android foreground service (`VeilAudioService`) ensuring continuous audio playback when the app is minimized or screen is locked.
- **Persistent Mini-Player**: Bottom floating audio pill visible across all library views with live progress bar and play/pause controls.
- **Queue Management**: Dynamic playback queue, Fisher-Yates shuffle, repeat modes (`Off`, `All`, `One`), and atomic JSON persistence (`AudioStorageService`) surviving app restarts.
- **System Media Integration**: MediaSession notification controls, lock screen media controls, Bluetooth click events, and smart AudioFocus (auto-pause on calls / headphone unplug).

### Smart Library & File Operations
- **Smart Quick Access**: Automatically detects and surfaces media directories including Camera, Downloads, Movies, and custom storage folders.
- **Noise Filtering**: Filters out thumbnails, cache directories, temporary files, `.nomedia` folders, zero-byte files, and messaging app stickers.
- **Watch History**: Preserves last-watched video, resume timestamps, and last-watched folder pointers.
- **File Management**: Rename, delete (via Storage Access Framework), copy/move clipboard, and native system file sharing.

### AMOLED Design & Zero Telemetry
- **AMOLED Pure Black Theme**: True `#000000` pitch-black design to conserve battery on OLED screens with fluid 120Hz micro-animations.
- **Zero Internet Permissions**: `android.permission.INTERNET` is completely absent from the Android Manifest. Veil Player cannot make network calls.
- **Local Diagnostics**: On-device crash and playback anomaly logging with automated privacy path sanitization.

---

## 📦 Download & Installation

### Release Assets
- **APK**: `app-release.apk`
- **Application ID**: `com.veil.player`
- **Version**: `1.0.0` (Build `1`)
- **Minimum OS**: Android 5.0 (API 21 / Lollipop)
- **Target OS**: Android 14 (API 34)

### How to Install
1. Download `app-release.apk` from the official GitHub Release assets below.
2. Open the downloaded `.apk` file on your Android device.
3. If prompted by Android, allow **"Install unknown apps"** for your browser or file manager.
4. Follow the prompt to complete installation.
5. Grant storage/media permissions when launching the app to allow Veil Player to discover your local media files.

> ⚠️ **Security Warning**: Download Veil Player exclusively from the official GitHub repository releases (`https://github.com/rohitmorerocks/Veil_Player/releases`). Never install APKs from unauthorized third-party mirrors.

---

## ⚠️ Known Limitations & Compatibility Notes

- **Android Exclusivity**: Veil Player is currently developed and tested exclusively for Android.
- **Codec Support**: Hardware decoding depends on your device's native `MediaCodec` chipset capabilities. Obscure formats fall back to CPU software decoding.
- **Scoped Storage**: Modifying or deleting files located on external SD cards on Android 11+ requires granting Storage Access Framework permissions.

---

## 📄 License & Source Code

Veil Player is open source under the [MIT License](LICENSE). 
Full source code and issue tracker are available at: [https://github.com/rohitmorerocks/Veil_Player](https://github.com/rohitmorerocks/Veil_Player).
