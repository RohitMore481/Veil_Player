import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../player/providers/player_settings_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({
    super.key,
    required this.onFinished,
  });

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late final Player _player;
  late final VideoController _controller;

  StreamSubscription? _positionSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _errorSubscription;
  Timer? _videoTimer;
  Timer? _safetyTimer;

  bool _hasRemovedNativeSplash = false;
  bool _isFinished = false;

  final Completer<void> _videoSplashCompleter = Completer<void>();
  late final Future<void> _appInitFuture;

  @override
  void initState() {
    super.initState();

    final settings = ref.read(playerSettingsProvider);
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: settings.hwDecoding,
      ),
    );

    _appInitFuture = _initApp();
    _initPlayer();
    _waitForCompletion();
  }

  Future<void> _initApp() async {
    try {
      // Force settings provider to load database configs in parallel.
      // The settings loading method loadSettings() was triggered in constructor, 
      // but we wait 400ms to allow concurrent settings & db reads to complete.
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      debugPrint('Error during app parallel init: $e');
    }
  }

  Future<void> _initPlayer() async {
    try {
      // Configure player playback: no controls, no loop, no audio
      await _player.setVolume(0.0);
      await _player.setPlaylistMode(PlaylistMode.none);

      // Listen for video runtime errors
      _errorSubscription = _player.stream.error.listen((error) {
        debugPrint('Splash video player error: $error');
        _finishSplash();
      });

      // Remove native splash as soon as the first frame plays
      _playingSubscription = _player.stream.playing.listen((playing) {
        if (playing && !_hasRemovedNativeSplash) {
          _removeNativeSplash();
        }
      });

      _positionSubscription = _player.stream.position.listen((pos) {
        if (pos > Duration.zero && !_hasRemovedNativeSplash) {
          _removeNativeSplash();
        }

        // Stop video exactly at the 2.9 seconds mark
        if (pos.inMilliseconds >= 2900) {
          _onVideoFinished();
        }
      });

      // Load asset video and start playback
      await _player.open(Media('asset://assets/splash/veil_boot.mp4'), play: false);
      await _player.play();

      // Backup timer to stop video after 2.9 seconds in case position updates delay
      _videoTimer = Timer(const Duration(milliseconds: 2900), () {
        _onVideoFinished();
      });
    } catch (e) {
      debugPrint('Splash video initialization failed: $e');
      _finishSplash();
    }
  }

  void _removeNativeSplash() {
    if (!_hasRemovedNativeSplash) {
      _hasRemovedNativeSplash = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          FlutterNativeSplash.remove();
        } catch (e) {
          debugPrint('Error removing native splash: $e');
        }
      });
    }
  }

  void _onVideoFinished() {
    if (_videoSplashCompleter.isCompleted) return;

    try {
      _player.pause();
    } catch (e) {
      debugPrint('Error pausing splash video: $e');
    }

    _videoSplashCompleter.complete();
    _videoTimer?.cancel();
  }

  Future<void> _waitForCompletion() async {
    // Safety fallback: Force entry to Home screen after 3.9s to ensure startup is never blocked
    _safetyTimer = Timer(const Duration(milliseconds: 3900), () {
      debugPrint('Splash screen safety fallback triggered.');
      _finishSplash();
    });

    try {
      await Future.wait([
        _videoSplashCompleter.future,
        _appInitFuture,
      ]);
    } catch (e) {
      debugPrint('Error waiting for splash completion: $e');
    }

    _finishSplash();
  }

  void _finishSplash() {
    if (_isFinished) return;
    _isFinished = true;

    _safetyTimer?.cancel();
    _videoTimer?.cancel();
    _removeNativeSplash();

    widget.onFinished();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    _videoTimer?.cancel();
    _safetyTimer?.cancel();

    // Release all video controller textures, memory, and native resources
    try {
      _player.dispose();
    } catch (e) {
      debugPrint('Error disposing splash player: $e');
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Pure AMOLED black background
      body: Center(
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 0.8, // 576 / 720 = 0.8. Crops bottom 20% to remove watermark
            child: AspectRatio(
              aspectRatio: 16 / 9, // Native 1280x720 video size
              child: Video(
                controller: _controller,
                controls: NoVideoControls,
                fit: BoxFit.fitWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
