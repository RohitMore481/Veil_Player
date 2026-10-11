# Changelog

All notable changes to Veil Player will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-12

### Added
- **Initial Public Release of Veil Player (v1.0.0+1)**.
- **Hardware-Accelerated Video Engine**: Powered by `media_kit` (libmpv backend) with hardware acceleration (`MediaCodec`) and automatic software fallback.
- **Intuitive Touch Gestures**: Left vertical swipe for brightness, right vertical swipe for volume, horizontal swipe for scrubbing with time delta overlay, double-tap 10s skip with ripples, and long-press 2x speed preview.
- **Dedicated Music & Audio Library**: Full audio player with Tracks, Folders, Playlists, and Search tabs.
- **Native Background Audio Service**: Android foreground service (`VeilAudioService`) ensuring continuous audio playback with screen off and lock screen controls.
- **Persistent Floating Mini-Player**: Bottom audio pill accessible across all library screens with live progress bar and play/pause controls.
- **Queue & Playlist Engine**: Reorderable playback queue, Fisher-Yates shuffle, repeat modes (`off`, `all`, `one`), and atomic JSON persistence (`AudioStorageService`).
- **Deep Android Media Integration**: MediaSession notification controls, Bluetooth click events, and smart AudioFocus (auto-pause on calls / headphone disconnect).
- **Subtitles & Audio Tracks**: Embedded audio and subtitle switching, automatic detection of external `.srt`, `.vtt`, `.ass`, `.ssa` files, and delay synchronization.
- **Picture-in-Picture (PiP)**: Native multitasking with aspect ratio preservation.
- **Display & Framing Controls**: Aspect ratio switcher (Fit, Stretch, 16:9, 4:3, Zoom), orientation locking, and touch-screen lock.
- **Smart Quick Access**: Automatic discovery of Camera, Downloads, Movies, and custom media folders with aggressive filtering of app cache, thumbnails, and messaging noise.
- **AMOLED Pure Black Theme**: Custom `#000000` pitch-black design system with fluid 120Hz micro-animations and battery optimization.
- **File Management**: Rename, delete via Android Storage Access Framework, copy/move clipboard, and native system file sharing.
- **Privacy-First Diagnostics**: Local-only crash and anomaly recording with automated multi-pass privacy path sanitizer, bounded retention, and user-initiated email reporting.
- **Zero Internet Requirement**: Completely offline with zero network permissions requested or declared.
