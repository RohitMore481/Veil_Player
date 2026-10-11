import 'package:flutter/foundation.dart';

/// Centralized media coordinator that enforces mutual exclusion between
/// video playback and audio playback.
///
/// Prevents concurrent audio and video playback across all screens and PiP.
class MediaCoordinator {
  static final MediaCoordinator instance = MediaCoordinator._internal();
  MediaCoordinator._internal();

  VoidCallback? _pauseVideoCallback;
  VoidCallback? _pauseAudioCallback;

  /// Registers the active video player's pause callback.
  void registerVideoSession({required VoidCallback pauseVideo}) {
    _pauseVideoCallback = pauseVideo;
  }

  /// Unregisters the video session callback. Only clears if matching.
  void unregisterVideoSession({VoidCallback? pauseVideo}) {
    if (pauseVideo == null || _pauseVideoCallback == pauseVideo) {
      _pauseVideoCallback = null;
    }
  }

  /// Registers the active audio player's pause callback.
  void registerAudioSession({required VoidCallback pauseAudio}) {
    _pauseAudioCallback = pauseAudio;
  }

  /// Unregisters the active audio player's pause callback. Only clears if matching.
  void unregisterAudioSession({VoidCallback? pauseAudio}) {
    if (pauseAudio == null || _pauseAudioCallback == pauseAudio) {
      _pauseAudioCallback = null;
    }
  }

  /// Called synchronously before starting audio playback.
  /// Immediately pauses active video playback if running.
  void onAudioStarting() {
    try {
      _pauseVideoCallback?.call();
    } catch (_) {}
  }

  /// Called synchronously before starting video playback.
  /// Immediately pauses active audio playback if running.
  void onVideoStarting() {
    try {
      _pauseAudioCallback?.call();
    } catch (_) {}
  }
}
