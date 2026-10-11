import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/core/media_coordinator/media_coordinator.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/audio_queue_state.dart';
import 'package:veil_player/features/audio_library/models/audio_settings.dart';
import 'package:veil_player/features/audio_library/models/queue_item.dart';
import 'package:veil_player/features/audio_library/providers/audio_player_provider.dart';
import 'package:veil_player/features/audio_library/services/audio_player_service.dart';
import 'package:veil_player/features/audio_library/services/audio_storage_service.dart';
import 'package:veil_player/features/library/services/media_service.dart';

class FakeAudioEngine implements AudioEngine {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  String? openedPath;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;

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
    openedPath = path;
    isPlaying = play;
    _playingController.add(play);
    _durationController.add(const Duration(minutes: 3));
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    currentPosition = position;
    _positionController.add(position);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    _playingController.add(false);
    _positionController.add(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _completedController.close();
    await _errorController.close();
  }

  void emitCompletion() {
    _completedController.add(true);
  }

  void emitError(String error) {
    _errorController.add(error);
  }

  void emitPosition(Duration position) {
    currentPosition = position;
    _positionController.add(position);
  }
}

class FakeAudioStorageService extends AudioStorageService {
  Map<String, dynamic>? savedQueueState;
  List<AudioTrackItem> savedRecentlyPlayed = [];
  AudioSettings savedSettings = const AudioSettings();

  @override
  Future<void> saveQueueState({
    required List<QueueItem> queue,
    required int currentIndex,
    required bool isShuffleEnabled,
    required AudioRepeatMode repeatMode,
    required Duration position,
  }) async {
    savedQueueState = {
      'queue': queue,
      'currentIndex': currentIndex,
      'isShuffleEnabled': isShuffleEnabled,
      'repeatMode': repeatMode,
      'position': position,
    };
  }

  @override
  Future<Map<String, dynamic>?> loadQueueState() async {
    return savedQueueState;
  }

  @override
  Future<void> saveRecentlyPlayed(List<AudioTrackItem> tracks) async {
    savedRecentlyPlayed = List.from(tracks);
  }

  @override
  Future<List<AudioTrackItem>> loadRecentlyPlayed() async {
    return savedRecentlyPlayed;
  }

  @override
  Future<void> saveSettings(AudioSettings settings) async {
    savedSettings = settings;
  }

  @override
  Future<AudioSettings> loadSettings() async {
    return savedSettings;
  }
}

class FakeMediaService extends MediaService {
  bool audioFocusRequested = false;
  bool audioFocusAbandoned = false;

  @override
  Future<bool> requestAudioFocus() async {
    audioFocusRequested = true;
    return true;
  }

  @override
  Future<void> abandonAudioFocus() async {
    audioFocusAbandoned = true;
  }
}

AudioTrackItem createTrack({
  required String id,
  required String title,
  String artist = 'Artist',
  int durationMs = 180000,
}) {
  return AudioTrackItem(
    id: id,
    title: title,
    artist: artist,
    album: 'Album',
    path: '/music/$title.mp3',
    contentUri: 'content://media/external/audio/media/$id',
    duration: Duration(milliseconds: durationMs),
    size: 5000000,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    folderName: 'Music',
    folderPath: '/music',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioEngine fakeEngine;
  late FakeAudioStorageService fakeStorage;
  late FakeMediaService fakeMediaService;
  late AudioPlayerService playerService;
  late AudioPlayerNotifier notifier;

  setUp(() {
    fakeEngine = FakeAudioEngine();
    fakeStorage = FakeAudioStorageService();
    fakeMediaService = FakeMediaService();
    playerService = AudioPlayerService(
      engine: fakeEngine,
      mediaService: fakeMediaService,
    );
    notifier = AudioPlayerNotifier(playerService, fakeStorage);
  });

  tearDown(() async {
    notifier.dispose();
    await playerService.dispose();
  });

  group('Queue Insertion & Duplicate Handling', () {
    test('Allows identical track added multiple times with distinct queueIds', () async {
      final track = createTrack(id: '1', title: 'Track 1');

      notifier.addTrack(track);
      notifier.addTrack(track);

      expect(notifier.state.queue.length, 2);
      expect(notifier.state.queue[0].track.id, '1');
      expect(notifier.state.queue[1].track.id, '1');
      expect(notifier.state.queue[0].queueId, isNot(equals(notifier.state.queue[1].queueId)));
    });

    test('PlayNow inserts and immediately plays track', () async {
      final track1 = createTrack(id: '1', title: 'Song 1');
      final track2 = createTrack(id: '2', title: 'Song 2');
      final trackNow = createTrack(id: '3', title: 'Now Song');

      await notifier.playTrackList([track1, track2], initialIndex: 0);
      expect(notifier.state.currentIndex, 0);

      await notifier.playNow(trackNow);

      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.queue[1].track.title, 'Now Song');
      expect(notifier.state.currentTrack?.title, 'Now Song');
      expect(fakeEngine.openedPath, '/music/Now Song.mp3');
      expect(fakeEngine.isPlaying, isTrue);
    });

    test('PlayNext inserts track immediately after current index', () async {
      final t1 = createTrack(id: '1', title: 'Song 1');
      final t2 = createTrack(id: '2', title: 'Song 2');
      final tNext = createTrack(id: '3', title: 'Next Song');

      await notifier.playTrackList([t1, t2], initialIndex: 0);
      notifier.playNext(tNext);

      expect(notifier.state.queue.length, 3);
      expect(notifier.state.queue[0].track.title, 'Song 1');
      expect(notifier.state.queue[1].track.title, 'Next Song');
      expect(notifier.state.queue[2].track.title, 'Song 2');
      expect(notifier.state.currentIndex, 0);
    });

    test('addMultipleToQueue appends multiple tracks', () async {
      final t1 = createTrack(id: '1', title: 'Song 1');
      final t2 = createTrack(id: '2', title: 'Song 2');
      final t3 = createTrack(id: '3', title: 'Song 3');

      notifier.addMultipleToQueue([t1, t2, t3]);

      expect(notifier.state.queue.length, 3);
      expect(notifier.state.queue[0].track.title, 'Song 1');
      expect(notifier.state.queue[1].track.title, 'Song 2');
      expect(notifier.state.queue[2].track.title, 'Song 3');
    });
  });

  group('Queue Reordering and Removal', () {
    test('Reordering current track updates currentIndex correctly', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');
      final t3 = createTrack(id: '3', title: 'C');

      await notifier.playTrackList([t1, t2, t3], initialIndex: 0);
      expect(notifier.state.currentIndex, 0);

      // Move A (0) to position 2 (after B and C)
      notifier.reorderQueue(0, 3);

      expect(notifier.state.queue[2].track.title, 'A');
      expect(notifier.state.currentIndex, 2);
      expect(notifier.state.currentTrack?.title, 'A');
    });

    test('Reordering track before current adjusts currentIndex', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');
      final t3 = createTrack(id: '3', title: 'C');

      await notifier.playTrackList([t1, t2, t3], initialIndex: 1); // Playing B at index 1

      // Move A from 0 to 2
      notifier.reorderQueue(0, 3);

      expect(notifier.state.currentIndex, 0); // B shifted left to 0
      expect(notifier.state.currentTrack?.title, 'B');
    });

    test('Removing current track plays the track at current index or wraps', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');
      final t3 = createTrack(id: '3', title: 'C');

      await notifier.playTrackList([t1, t2, t3], initialIndex: 1); // Playing B (queue[1])
      final bQueueId = notifier.state.queue[1].queueId;

      await notifier.removeQueueItem(bQueueId);

      expect(notifier.state.queue.length, 2);
      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.currentTrack?.title, 'C');
    });

    test('Removing non-current track before current decrements currentIndex', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');
      final t3 = createTrack(id: '3', title: 'C');

      await notifier.playTrackList([t1, t2, t3], initialIndex: 2); // Playing C at index 2
      final aQueueId = notifier.state.queue[0].queueId;

      await notifier.removeQueueItem(aQueueId);

      expect(notifier.state.queue.length, 2);
      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.currentTrack?.title, 'C');
    });

    test('Clearing queue resets state and stops playback', () async {
      final t1 = createTrack(id: '1', title: 'A');
      await notifier.playTrackList([t1], initialIndex: 0);

      await notifier.clearQueue();

      expect(notifier.state.isEmpty, isTrue);
      expect(notifier.state.currentIndex, -1);
      expect(notifier.state.isPlaying, isFalse);
      expect(fakeEngine.isPlaying, isFalse);
    });
  });

  group('Repeat and Shuffle Behavior', () {
    test('Repeat Mode cycles Off -> All -> One -> Off', () {
      expect(notifier.state.repeatMode, AudioRepeatMode.off);

      notifier.cycleRepeatMode();
      expect(notifier.state.repeatMode, AudioRepeatMode.all);

      notifier.cycleRepeatMode();
      expect(notifier.state.repeatMode, AudioRepeatMode.one);

      notifier.cycleRepeatMode();
      expect(notifier.state.repeatMode, AudioRepeatMode.off);
    });

    test('Toggling shuffle builds indices without mutating queue list', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');
      final t3 = createTrack(id: '3', title: 'C');
      final t4 = createTrack(id: '4', title: 'D');

      await notifier.playTrackList([t1, t2, t3, t4], initialIndex: 0);

      notifier.toggleShuffle();

      expect(notifier.state.isShuffleEnabled, isTrue);
      expect(notifier.state.shuffleIndices.length, 4);
      expect(notifier.state.shuffleIndices.first, 0); // Current track kept first

      // Visible queue retains exact original order
      expect(notifier.state.queue[0].track.title, 'A');
      expect(notifier.state.queue[1].track.title, 'B');
      expect(notifier.state.queue[2].track.title, 'C');
      expect(notifier.state.queue[3].track.title, 'D');

      notifier.toggleShuffle();
      expect(notifier.state.isShuffleEnabled, isFalse);
      expect(notifier.state.queue[0].track.title, 'A');
      expect(notifier.state.queue[1].track.title, 'B');
      expect(notifier.state.queue[2].track.title, 'C');
      expect(notifier.state.queue[3].track.title, 'D');
    });

    test('Next track progression on track completion', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');

      await notifier.playTrackList([t1, t2], initialIndex: 0);
      expect(notifier.state.currentIndex, 0);

      // Track 1 completes
      fakeEngine.emitCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.currentTrack?.title, 'B');
    });

    test('Repeat One restarts current track on completion', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');

      await notifier.playTrackList([t1, t2], initialIndex: 0);
      notifier.cycleRepeatMode(); // All
      notifier.cycleRepeatMode(); // One
      expect(notifier.state.repeatMode, AudioRepeatMode.one);

      fakeEngine.emitCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.currentIndex, 0);
      expect(notifier.state.currentTrack?.title, 'A');
    });

    test('Repeat All wraps to first track on last track completion', () async {
      final t1 = createTrack(id: '1', title: 'A');
      final t2 = createTrack(id: '2', title: 'B');

      await notifier.playTrackList([t1, t2], initialIndex: 1); // Last track
      notifier.cycleRepeatMode(); // All
      expect(notifier.state.repeatMode, AudioRepeatMode.all);

      fakeEngine.emitCompletion();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.currentIndex, 0);
      expect(notifier.state.currentTrack?.title, 'A');
    });
  });

  group('MediaCoordinator Audio/Video Mutual Exclusion', () {
    test('Starting video synchronously pauses active audio', () async {
      final coordinator = MediaCoordinator.instance;
      bool videoPaused = false;
      bool audioPaused = false;

      coordinator.registerVideoSession(pauseVideo: () {
        videoPaused = true;
      });
      coordinator.registerAudioSession(pauseAudio: () {
        audioPaused = true;
      });

      // Video starting must pause audio
      coordinator.onVideoStarting();
      expect(audioPaused, isTrue);

      // Audio starting must pause video
      coordinator.onAudioStarting();
      expect(videoPaused, isTrue);

      coordinator.unregisterVideoSession();
      coordinator.unregisterAudioSession();
    });

    test('Unregistering video does not pause audio session', () {
      final coordinator = MediaCoordinator.instance;
      bool audioPaused = false;

      coordinator.registerAudioSession(pauseAudio: () {
        audioPaused = true;
      });

      coordinator.unregisterVideoSession();
      expect(audioPaused, isFalse);

      coordinator.unregisterAudioSession();
    });
  });

  group('Persistence and Restoration', () {
    test('Queue state is persisted into storage on changes', () async {
      final t1 = createTrack(id: '1', title: 'Song 1');
      await notifier.playTrackList([t1], initialIndex: 0);

      expect(fakeStorage.savedQueueState, isNotNull);
      final queue = fakeStorage.savedQueueState!['queue'] as List<QueueItem>;
      expect(queue.length, 1);
      expect(queue[0].track.title, 'Song 1');
      expect(fakeStorage.savedQueueState!['currentIndex'], 0);
    });

    test('Recently played tracks list is updated on playback', () async {
      final t1 = createTrack(id: '1', title: 'Song 1');
      await notifier.playTrackList([t1], initialIndex: 0);

      expect(fakeStorage.savedRecentlyPlayed.length, 1);
      expect(fakeStorage.savedRecentlyPlayed.first.title, 'Song 1');
      expect(notifier.recentlyPlayed.first.title, 'Song 1');
    });
  });

  group('Error Handling', () {
    test('Engine error updates state errorMessage and advances on error', () async {
      final t1 = createTrack(id: '1', title: 'Corrupted Track');
      final t2 = createTrack(id: '2', title: 'Healthy Track');

      await notifier.playTrackList([t1, t2], initialIndex: 0);

      fakeEngine.emitError('Unsupported codec or missing file');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.currentIndex, 1);
      expect(notifier.state.currentTrack?.title, 'Healthy Track');
    });

    test('jumpToIndex jumps directly without replacing queue or altering queueIds', () async {
      final t1 = createTrack(id: '1', title: 'Song 1');
      final t2 = createTrack(id: '2', title: 'Song 2');
      final t3 = createTrack(id: '3', title: 'Song 3');

      await notifier.playTrackList([t1, t2, t3], initialIndex: 0);
      final initialQueueIds = notifier.state.queue.map((q) => q.queueId).toList();

      await notifier.jumpToIndex(2);

      expect(notifier.state.currentIndex, 2);
      expect(notifier.state.currentTrack?.title, 'Song 3');
      final currentQueueIds = notifier.state.queue.map((q) => q.queueId).toList();
      expect(currentQueueIds, equals(initialQueueIds));
    });

    test('Consecutive failures limiter stops after 3 errors and prevents infinite skip loop', () async {
      final t1 = createTrack(id: '1', title: 'Bad 1');
      final t2 = createTrack(id: '2', title: 'Bad 2');
      final t3 = createTrack(id: '3', title: 'Bad 3');
      final t4 = createTrack(id: '4', title: 'Bad 4');
      final t5 = createTrack(id: '5', title: 'Healthy');

      await notifier.playTrackList([t1, t2, t3, t4, t5], initialIndex: 0);

      // Emit 3 consecutive errors
      fakeEngine.emitError('Err 1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      fakeEngine.emitError('Err 2');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      fakeEngine.emitError('Err 3');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // After 3 consecutive failures, it stops advancing automatically to prevent infinite skip loop
      expect(notifier.state.isPlaying, isFalse);
      expect(notifier.state.errorMessage, contains('Playback stopped after repeated failures'));
    });
  });
}
