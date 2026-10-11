<p align="center">
  <img src="assets/images/app_icon.png" width="200" alt="Veil Player Logo">
</p>

<h1 align="center">Veil Player</h1>

<p align="center">
  <strong>The premium, offline-first, AMOLED-optimized Android media player.</strong>
</p>

---

## 🎬 About Veil Player

Veil Player is a lightning-fast, privacy-respecting local media player built for modern Android devices. Designed with a strict offline-first philosophy, it guarantees zero telemetry, zero ads, and zero network calls.

Powered by `media_kit` (libmpv), Veil Player leverages native hardware acceleration to handle 4K 120fps video files with ease, while falling back to robust software decoding for legacy codecs.

## ✨ Key Features

- **Unmatched Playback**: Hardware decoding, precise subtitle timing adjustments, multi-track audio switching, and pitch-corrected playback speeds.
- **Smart Quick Access**: The library intelligently auto-discovers your Camera, Downloads, and Movies folders while aggressively filtering out system cache, thumbnails, and messaging app stickers.
- **AMOLED Pure Black**: The entire UI is built on a true `#000000` pitch-black theme, actively turning off pixels to save battery during usage.
- **Fluid 120Hz Animations**: Every interaction is tied to a unified physics-based motion system, ensuring buttery-smooth transitions and micro-animations.
- **Deep Android Integration**: 
  - Native Picture-in-Picture (PiP) multitasking.
  - Background playback with MediaSession lock-screen controls.
  - Automatic AudioFocus handling (pauses on calls, resumes on Bluetooth connect).
- **Advanced File Management**: Safely delete, rename, hide, and share files directly through the Android Storage Access Framework without redundant media scanning.

## 🚀 Version 1.0 Status

Veil Player is currently in **Release Freeze** for Version 1.0. 
The core engine, UI, and feature set are locked and deemed production-ready.

- [Release Notes](Release_Notes.md)
- [Changelog](CHANGELOG.md)
- [Contributing Guidelines](CONTRIBUTING.md)

## 🛠 Tech Stack

- **Frontend**: Flutter & Dart (Riverpod for state management)
- **Backend / Platform Channels**: Native Android Kotlin
- **Media Engine**: `media_kit` 

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
