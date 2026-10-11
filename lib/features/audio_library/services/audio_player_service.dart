import 'dart:async';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/media_coordinator/media_coordinator.dart';
import '../../../core/utils/method_channel_dispatcher.dart';
import '../../library/services/media_service.dart';

abstract class AudioEngine {
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<String> get errorStream;

  Future<void> open(String path, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}

class MediaKitAudioEngine implements AudioEngine {
  final Player _player;

  MediaKitAudioEngine({Player? player})
      : _player = player ??
            Player(
              configuration: const PlayerConfiguration(
                bufferSize: 16 * 1024 * 1024,
              ),
            );

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Future<void> open(String path, {bool play = true}) async {
    await _player.open(Media(path), play: play);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}

class NoOpAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<bool> get completedStream => _completedController.stream;
  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Future<void> open(String path, {bool play = true}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _completedController.close();
    await _errorController.close();
  }
}

class AudioPlayerService {
  final AudioEngine _engine;
  final MediaService _mediaService;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _compSub;
  StreamSubscription? _errSub;

  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _durationController = StreamController<Duration>.broadcast(sync: true);
  final _playingController = StreamController<bool>.broadcast(sync: true);
  final _completedController = StreamController<void>.broadcast(sync: true);
  final _errorController = StreamController<String>.broadcast(sync: true);

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<void> get completedStream => _completedController.stream;
  Stream<String> get errorStream => _errorController.stream;

  String? _openedPath;
  String? get openedPath => _openedPath;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  // Delegates for queue-level remote command handling
  void Function()? onPlayRequested;
  void Function()? onPauseRequested;
  void Function()? onToggleRequested;
  void Function()? onNextRequested;
  void Function()? onPreviousRequested;
  void Function(Duration position)? onSeekRequested;

  AudioPlayerService({
    AudioEngine? engine,
    MediaService? mediaService,
  })  : _engine = engine ?? _createDefaultEngine(),
        _mediaService = mediaService ?? MediaService() {
    _initStreams();
    MediaCoordinator.instance.registerAudioSession(pauseAudio: pause);
    MethodChannelDispatcher.addListener(_handleMethodCall);
  }

  static AudioEngine _createDefaultEngine() {
    try {
      return MediaKitAudioEngine();
    } catch (_) {
      return NoOpAudioEngine();
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMediaButtonPlay':
        onPlayRequested != null ? onPlayRequested!() : await play();
        break;
      case 'onMediaButtonPause':
        onPauseRequested != null ? onPauseRequested!() : await pause();
        break;
      case 'onMediaButtonToggle':
        onToggleRequested != null
            ? onToggleRequested!()
            : (_isPlaying ? await pause() : await play());
        break;
      case 'onMediaButtonNext':
        onNextRequested?.call();
        break;
      case 'onMediaButtonPrevious':
        onPreviousRequested?.call();
        break;
      case 'onMediaButtonSeekTo':
        final posMs = (call.arguments as num?)?.toInt() ?? 0;
        final targetPos = Duration(milliseconds: posMs);
        onSeekRequested != null ? onSeekRequested!(targetPos) : await seek(targetPos);
        break;
      case 'onAudioFocusLoss':
        // Loss of audio focus: pause audio
        onPauseRequested != null ? onPauseRequested!() : await pause();
        break;
      case 'onBecomingNoisy':
        // Headphones unplugged: pause audio
        onPauseRequested != null ? onPauseRequested!() : await pause();
        break;
    }
    return null;
  }

  void _initStreams() {
    _posSub = _engine.positionStream.listen((pos) {
      _positionController.add(pos);
    });

    _durSub = _engine.durationStream.listen((dur) {
      _durationController.add(dur);
    });

    _playSub = _engine.playingStream.listen((playing) {
      _isPlaying = playing;
      _playingController.add(playing);
    });

    _compSub = _engine.completedStream.listen((completed) {
      if (completed) {
        _completedController.add(null);
      }
    });

    _errSub = _engine.errorStream.listen((err) {
      _errorController.add(err);
    });
  }

  Future<void> updateNotification({
    required String title,
    required String artist,
    String? album,
    required bool isPlaying,
    bool? hasNext,
    bool? hasPrevious,
    required Duration position,
    required Duration duration,
  }) async {
    await _mediaService.updateAudioService(
      title: title,
      artist: artist,
      isPlaying: isPlaying,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
    );
  }

  Future<void> stopNotification() async {
    await _mediaService.stopAudioService();
  }

  Future<void> open(String path, {bool play = true}) async {
    if (play) {
      // Coordinate with video: pause active video before audio starts
      MediaCoordinator.instance.onAudioStarting();
    }
    _openedPath = path;
    _isPlaying = play;
    try {
      await _engine.open(path, play: play);
    } catch (e) {
      _openedPath = null;
      _isPlaying = false;
      _errorController.add(e.toString());
      rethrow;
    }
  }

  Future<void> play() async {
    MediaCoordinator.instance.onAudioStarting();
    _isPlaying = true;
    await _engine.play();
  }

  Future<void> pause() async {
    _isPlaying = false;
    await _engine.pause();
  }

  Future<void> seek(Duration position) async {
    await _engine.seek(position);
  }

  Future<void> stop() async {
    _openedPath = null;
    await _engine.stop();
    await stopNotification();
  }

  Future<void> dispose() async {
    MethodChannelDispatcher.removeListener(_handleMethodCall);
    MediaCoordinator.instance.unregisterAudioSession();
    await stopNotification();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _playSub?.cancel();
    await _compSub?.cancel();
    await _errSub?.cancel();

    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _completedController.close();
    await _errorController.close();

    await _engine.dispose();
  }
}
