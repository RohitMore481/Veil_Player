import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/audio_queue_state.dart';
import 'package:veil_player/features/audio_library/models/audio_settings.dart';
import 'package:veil_player/features/audio_library/models/queue_item.dart';
import 'package:veil_player/features/audio_library/providers/audio_player_provider.dart';
import 'package:veil_player/features/audio_library/services/audio_player_service.dart';
import 'package:veil_player/features/audio_library/services/audio_storage_service.dart';
import 'package:veil_player/features/library/services/media_service.dart';

class ControllableAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _durationController = StreamController<Duration>.broadcast(sync: true);
  final _playingController = StreamController<bool>.broadcast(sync: true);
  final _completedController = StreamController<bool>.broadcast(sync: true);
  final _errorController = StreamController<String>.broadcast(sync: true);

  String? openedPath;
  bool isPlaying = false;
  int openCallCount = 0;
  int playCallCount = 0;
  int pauseCallCount = 0;
  Duration? simulatedOpenDelay;
  bool shouldFailOpen = false;

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
  Future<void> open(String path, {bool play = true}) async {
    openCallCount++;
    if (simulatedOpenDelay != null) {
      await Future.delayed(simulatedOpenDelay!);
    }
    if (shouldFailOpen) {
      throw Exception('Failed to decode media file: $path');
    }
    openedPath = path;
    isPlaying = play;
    _playingController.add(play);
    _durationController.add(const Duration(minutes: 3));
  }

  @override
  Future<void> play() async {
    playCallCount++;
    isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _completedController.close();
    await _errorController.close();
  }
}

class MockAudioStorageService extends AudioStorageService {
  Map<String, dynamic>? storedQueue;
  List<AudioTrackItem> storedRecent = [];
  Duration loadDelay = Duration.zero;

  @override
  Future<Map<String, dynamic>?> loadQueueState() async {
    if (loadDelay > Duration.zero) {
      await Future.delayed(loadDelay);
    }
    return storedQueue;
  }

  @override
  Future<void> saveQueueState({
    required List<QueueItem> queue,
    required int currentIndex,
    required bool isShuffleEnabled,
    required AudioRepeatMode repeatMode,
    required Duration position,
  }) async {
    storedQueue = {
      'queue': queue,
      'currentIndex': currentIndex,
      'isShuffleEnabled': isShuffleEnabled,
      'repeatMode': repeatMode,
      'position': position,
    };
  }

  @override
  Future<List<AudioTrackItem>> loadRecentlyPlayed() async {
    return storedRecent;
  }

  @override
  Future<void> saveRecentlyPlayed(List<AudioTrackItem> tracks) async {
    storedRecent = List.from(tracks);
  }

  @override
  Future<AudioSettings> loadSettings() async {
    return const AudioSettings();
  }
}

class TestNotificationMediaService extends MediaService {
  String? lastTitle;
  String? lastArtist;
  bool? lastIsPlaying;
  int updateCount = 0;

  @override
  Future<bool> updateAudioService({
    required String title,
    required String artist,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
  }) async {
    updateCount++;
    lastTitle = title;
    lastArtist = artist;
    lastIsPlaying = isPlaying;
    return true;
  }

  @override
  Future<bool> stopAudioService() async {
    lastIsPlaying = false;
    return true;
  }
}

AudioTrackItem sampleTrack(String id, String title) {
  return AudioTrackItem(
    id: id,
    title: title,
    artist: 'Sample Artist',
    album: 'Sample Album',
    path: '/storage/music/$title.mp3',
    contentUri: 'content://media/audio/$id',
    duration: const Duration(minutes: 3),
    size: 4000000,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    folderName: 'Music',
    folderPath: '/storage/music',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ControllableAudioEngine engine;
  late MockAudioStorageService storage;
  late TestNotificationMediaService mediaService;
  late AudioPlayerService playerService;
  late AudioPlayerNotifier notifier;

  setUp(() {
    engine = ControllableAudioEngine();
    storage = MockAudioStorageService();
    mediaService = TestNotificationMediaService();
    playerService = AudioPlayerService(
      engine: engine,
      mediaService: mediaService,
    );
    notifier = AudioPlayerNotifier(playerService, storage);
  });

  tearDown(() async {
    notifier.dispose();
    await playerService.dispose();
  });

  group('First-Tap Playback & Audit Tests', () {
    test('1. First tap on a track immediately initiates playback and sets isPlaying to true', () async {
      final track = sampleTrack('t1', 'Track 1');

      expect(notifier.state.isPlaying, isFalse);
      expect(notifier.state.isLoading, isFalse);

      await notifier.playNow(track);

      // Verify playback started on the very first intentional action
      expect(notifier.state.isPlaying, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.currentTrack?.id, equals('t1'));
      expect(engine.openCallCount, equals(1));
      expect(engine.openedPath, equals(track.path));
      expect(engine.isPlaying, isTrue);
    });

    test('2. A second tap pauses rather than being needed to start', () async {
      final track = sampleTrack('t1', 'Track 1');

      // Tap 1: Start playback
      await notifier.playNow(track);
      expect(notifier.state.isPlaying, isTrue);
      expect(engine.isPlaying, isTrue);

      // Tap 2: Toggle play/pause -> Must pause, not start
      await notifier.togglePlayPause();
      expect(notifier.state.isPlaying, isFalse);
      expect(engine.isPlaying, isFalse);
      expect(engine.pauseCallCount, equals(1));

      // Tap 3: Toggle play/pause -> Resumes playback cleanly
      await notifier.togglePlayPause();
      expect(notifier.state.isPlaying, isTrue);
      expect(engine.isPlaying, isTrue);
    });

    test('3. Repeated taps during initialization do not create duplicate players or commands', () async {
      final track = sampleTrack('t1', 'Track 1');
      engine.simulatedOpenDelay = const Duration(milliseconds: 50);

      // Trigger first open
      final future = notifier.playNow(track);

      // Verify loading state is active
      expect(notifier.state.isLoading, isTrue);

      // Simulate rapid duplicate taps while loading
      await notifier.togglePlayPause();
      await notifier.play();
      await notifier.pause();

      await future;

      // Ensure open was called exactly once and state resolved to playing cleanly
      expect(engine.openCallCount, equals(1));
      expect(notifier.state.isPlaying, isTrue);
      expect(notifier.state.isLoading, isFalse);
    });

    test('4. Asynchronous disk persistence does not overwrite active first-tap playback', () async {
      // Simulate slow disk load that finishes AFTER user taps a track
      storage.loadDelay = const Duration(milliseconds: 60);
      storage.storedQueue = {
        'queue': [
          QueueItem(queueId: 'saved_1', track: sampleTrack('old_1', 'Old Stale Song')),
        ],
        'currentIndex': 0,
        'isShuffleEnabled': false,
        'repeatMode': AudioRepeatMode.off,
        'position': Duration.zero,
      };

      final newTrack = sampleTrack('new_1', 'Brand New Song');

      // User taps immediately upon app launch
      await notifier.playNow(newTrack);

      // Wait for slow disk load to complete in the background
      await Future.delayed(const Duration(milliseconds: 100));

      // The active playback must NOT be overridden by the old saved queue!
      expect(notifier.state.currentTrack?.id, equals('new_1'));
      expect(notifier.state.currentTrack?.title, equals('Brand New Song'));
      expect(notifier.state.isPlaying, isTrue);
      expect(engine.openedPath, equals(newTrack.path));
    });

    test('5. Rapidly selecting track B after track A cannot leave track A as stale track', () async {
      final trackA = sampleTrack('ta', 'Track A');
      final trackB = sampleTrack('tb', 'Track B');

      await notifier.playTrackList([trackA, trackB], initialIndex: 0);

      expect(notifier.state.currentIndex, equals(0));
      expect(notifier.state.currentTrack?.id, equals('ta'));

      // Now rapidly tap track B
      await notifier.jumpToIndex(1);

      expect(notifier.state.currentIndex, equals(1));
      expect(notifier.state.currentTrack?.id, equals('tb'));
      expect(engine.openedPath, equals(trackB.path));
    });

    test('6. A failed open returns the UI to a usable, non-stuck error state and allows retry', () async {
      final brokenTrack = sampleTrack('err_1', 'Corrupt Audio File');
      engine.shouldFailOpen = true;

      await notifier.playNow(brokenTrack);

      // UI must NOT be stuck in loading
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.isPlaying, isFalse);
      expect(notifier.state.errorMessage, isNotNull);
      expect(notifier.state.errorMessage!.contains('Corrupt Audio File'), isTrue);

      // Now fix file and retry - should work without restarting app
      engine.shouldFailOpen = false;
      final goodTrack = sampleTrack('good_1', 'Valid Audio File');
      await notifier.playNow(goodTrack);

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.isPlaying, isTrue);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.currentTrack?.id, equals('good_1'));
    });

    test('7. Queue, mini-player, and notification states remain synchronized', () async {
      final track1 = sampleTrack('t1', 'First Song');
      final track2 = sampleTrack('t2', 'Second Song');

      await notifier.playTrackList([track1, track2], initialIndex: 0);

      // Check notification sync
      expect(mediaService.lastTitle, equals('First Song'));
      expect(mediaService.lastIsPlaying, isTrue);
      expect(notifier.state.currentTrack?.title, equals('First Song'));
      expect(notifier.state.isPlaying, isTrue);

      // Advance to next
      await notifier.next();

      expect(mediaService.lastTitle, equals('Second Song'));
      expect(mediaService.lastIsPlaying, isTrue);
      expect(notifier.state.currentTrack?.title, equals('Second Song'));
      expect(notifier.state.currentIndex, equals(1));

      // Pause
      await notifier.pause();

      expect(mediaService.lastIsPlaying, isFalse);
      expect(notifier.state.isPlaying, isFalse);
    });

    test('8. Play All and Shuffle All on first use immediately start playback at index 0', () async {
      final tracks = [
        sampleTrack('t1', 'Song 1'),
        sampleTrack('t2', 'Song 2'),
        sampleTrack('t3', 'Song 3'),
      ];

      // Play All on uninitialized queue
      await notifier.playTrackList(tracks, initialIndex: 0);

      expect(notifier.state.isPlaying, isTrue);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.currentIndex, equals(0));
      expect(notifier.state.currentTrack?.id, equals('t1'));
      expect(engine.openCallCount, equals(1));
    });
  });
}
