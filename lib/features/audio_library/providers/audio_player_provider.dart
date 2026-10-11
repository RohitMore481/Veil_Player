import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_item.dart';
import '../models/audio_queue_state.dart';
import '../models/audio_settings.dart';
import '../models/queue_item.dart';
import '../services/audio_player_service.dart';
import '../services/audio_storage_service.dart';

final audioStorageServiceProvider = Provider<AudioStorageService>((ref) {
  return AudioStorageService();
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

class AudioPlayerNotifier extends StateNotifier<AudioQueueState> {
  final AudioPlayerService _playerService;
  final AudioStorageService _storageService;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _playSub;
  StreamSubscription? _compSub;
  StreamSubscription? _errSub;

  List<AudioTrackItem> _recentlyPlayed = [];
  List<AudioTrackItem> get recentlyPlayed => _recentlyPlayed;

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  bool _sleepTimerEndOfTrack = false;
  Duration? _sleepTimerDuration;
  Duration? get sleepTimerDuration => _sleepTimerDuration;

  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndTime == null) return null;
    final diff = _sleepTimerEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isSleepTimerActive =>
      _sleepTimerEndTime != null || _sleepTimerEndOfTrack;

  String? get activeSleepTimerLabel {
    if (_sleepTimerEndOfTrack) return 'End of track';
    final remaining = sleepTimerRemaining;
    if (remaining == null) return null;
    final minutes = remaining.inMinutes;
    if (minutes > 0) return '${minutes}m left';
    final seconds = remaining.inSeconds;
    return '${seconds}s left';
  }

  int _queueIdCounter = 0;

  AudioPlayerNotifier(
    this._playerService,
    this._storageService,
  ) : super(const AudioQueueState()) {
    _init();
  }

  String _generateQueueId() {
    _queueIdCounter++;
    return 'q_${DateTime.now().millisecondsSinceEpoch}_$_queueIdCounter';
  }

  Future<void> _init() async {
    _listenPlayerStreams();
    _setupRemoteCommandDelegates();
    await _loadPersistedData();
  }

  void _setupRemoteCommandDelegates() {
    _playerService.onPlayRequested = play;
    _playerService.onPauseRequested = pause;
    _playerService.onToggleRequested = togglePlayPause;
    _playerService.onNextRequested = next;
    _playerService.onPreviousRequested = previous;
    _playerService.onSeekRequested = (pos) => seek(pos);
  }

  void _listenPlayerStreams() {
    _posSub = _playerService.positionStream.listen((pos) {
      if (pos.inSeconds >= 1 && _consecutiveFailures > 0) {
        _consecutiveFailures = 0;
      }
      state = state.copyWith(position: pos);
    });

    _durSub = _playerService.durationStream.listen((dur) {
      state = state.copyWith(duration: dur);
    });

    _playSub = _playerService.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
      _updateNotification();
    });

    _compSub = _playerService.completedStream.listen((_) {
      _onTrackCompleted();
    });

    _errSub = _playerService.errorStream.listen((err) {
      _consecutiveFailures++;
      state = state.copyWith(errorMessage: err, isLoading: false);
      // Advance on error to prevent being stuck on broken file, up to max limit
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _consecutiveFailures = 0;
        pause();
        state = state.copyWith(
          isPlaying: false,
          errorMessage: 'Playback stopped after repeated failures.',
        );
        _updateNotification();
      } else if (state.hasNext) {
        next();
      }
    });
  }

  Future<void> _loadPersistedData() async {
    try {
      _recentlyPlayed = await _storageService.loadRecentlyPlayed();
      final settings = await _storageService.loadSettings();
      final savedState = await _storageService.loadQueueState();

      if (savedState != null) {
        final List<QueueItem> queue =
            (savedState['queue'] as List<QueueItem>?) ?? [];
        final int currentIndex = savedState['currentIndex'] as int? ?? -1;
        final bool isShuffle = savedState['isShuffleEnabled'] as bool? ?? false;
        final AudioRepeatMode repeatMode =
            savedState['repeatMode'] as AudioRepeatMode? ??
                settings.defaultRepeatMode;
        final Duration savedPosition =
            savedState['position'] as Duration? ?? Duration.zero;

        List<int> shuffleIndices = [];
        if (isShuffle && queue.isNotEmpty) {
          shuffleIndices = _buildShuffleIndices(queue.length, currentIndex);
        }

        state = state.copyWith(
          queue: queue,
          currentIndex: currentIndex,
          isShuffleEnabled: isShuffle,
          shuffleIndices: shuffleIndices,
          repeatMode: repeatMode,
          position: savedPosition,
        );

        // Preload current track in paused state so user can resume if file exists
        if (currentIndex >= 0 && currentIndex < queue.length) {
          final current = queue[currentIndex];
          try {
            await _playerService.open(current.track.path, play: false);
            if (savedPosition > Duration.zero) {
              await _playerService.seek(savedPosition);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  List<int> _buildShuffleIndices(int length, int current) {
    final list = List<int>.generate(length, (i) => i);
    list.remove(current);
    list.shuffle(Random());
    if (current >= 0 && current < length) {
      list.insert(0, current);
    }
    return list;
  }

  Future<void> _saveQueue() async {
    await _storageService.saveQueueState(
      queue: state.queue,
      currentIndex: state.currentIndex,
      isShuffleEnabled: state.isShuffleEnabled,
      repeatMode: state.repeatMode,
      position: state.position,
    );
  }

  void _recordRecentlyPlayed(AudioTrackItem track) {
    _recentlyPlayed.removeWhere((t) => t.id == track.id);
    _recentlyPlayed.insert(0, track);
    if (_recentlyPlayed.length > 50) {
      _recentlyPlayed = _recentlyPlayed.sublist(0, 50);
    }
    _storageService.saveRecentlyPlayed(_recentlyPlayed);
  }

  Future<void> clearRecentlyPlayed() async {
    _recentlyPlayed.clear();
    await _storageService.saveRecentlyPlayed(_recentlyPlayed);
    state = state.copyWith();
  }

  Future<void> removeRecentlyPlayedTrack(String id) async {
    _recentlyPlayed.removeWhere((t) => t.id == id);
    await _storageService.saveRecentlyPlayed(_recentlyPlayed);
    state = state.copyWith();
  }

  // --- Playback Commands ---

  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;

  void _updateNotification() {
    final current = state.currentTrack;
    if (current != null) {
      final hasNext = state.isShuffleEnabled
          ? (state.shuffleIndices.indexOf(state.currentIndex) < state.shuffleIndices.length - 1 || state.repeatMode == AudioRepeatMode.all)
          : (state.hasNext || state.repeatMode == AudioRepeatMode.all);
      final hasPrev = state.isShuffleEnabled
          ? (state.shuffleIndices.indexOf(state.currentIndex) > 0 || state.repeatMode == AudioRepeatMode.all)
          : (state.currentIndex > 0 || state.repeatMode == AudioRepeatMode.all);

      _playerService.updateNotification(
        title: current.title,
        artist: current.artist,
        album: current.album,
        isPlaying: state.isPlaying,
        hasNext: hasNext,
        hasPrevious: hasPrev,
        duration: state.duration,
        position: state.position,
      );
    } else {
      _playerService.stopNotification();
    }
  }

  Future<void> jumpToIndex(int index) async {
    _consecutiveFailures = 0;
    if (index >= 0 && index < state.queue.length) {
      await _playTrackAtIndex(index);
    }
  }

  Future<void> _playTrackAtIndex(int index, {Duration? startPosition}) async {
    if (index < 0 || index >= state.queue.length) return;

    state = state.copyWith(
      currentIndex: index,
      isLoading: true,
      clearError: true,
    );

    final track = state.queue[index].track;

    try {
      await _playerService.open(track.path, play: true);
      _recordRecentlyPlayed(track);
      if (startPosition != null && startPosition > Duration.zero) {
        await _playerService.seek(startPosition);
      }
      state = state.copyWith(isLoading: false, isPlaying: true);
      _updateNotification();
      _saveQueue();
    } catch (e) {
      _consecutiveFailures++;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to play "${track.title}": $e',
      );
      if (_consecutiveFailures < _maxConsecutiveFailures && state.hasNext) {
        await next();
      } else {
        _consecutiveFailures = 0;
        await pause();
        state = state.copyWith(isPlaying: false);
        _updateNotification();
      }
    }
  }

  Future<void> play() async {
    if (state.isEmpty) return;
    if (state.currentIndex == -1) {
      await _playTrackAtIndex(0);
      return;
    }
    await _playerService.play();
    _updateNotification();
  }

  Future<void> pause() async {
    await _playerService.pause();
    _updateNotification();
    _saveQueue();
  }

  Future<void> stop() async {
    await _playerService.stop();
    _playerService.stopNotification();
    state = state.copyWith(isPlaying: false, position: Duration.zero);
    _saveQueue();
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    await _playerService.seek(position);
    state = state.copyWith(position: position);
  }

  Future<void> next() async {
    if (state.isEmpty) return;

    if (state.repeatMode == AudioRepeatMode.one) {
      // Manual next advances even in repeat one mode
    }

    if (state.isShuffleEnabled && state.shuffleIndices.isNotEmpty) {
      final currentPosInShuffle =
          state.shuffleIndices.indexOf(state.currentIndex);
      if (currentPosInShuffle >= 0 &&
          currentPosInShuffle < state.shuffleIndices.length - 1) {
        final nextIdx = state.shuffleIndices[currentPosInShuffle + 1];
        await _playTrackAtIndex(nextIdx);
        return;
      } else if (state.repeatMode == AudioRepeatMode.all) {
        final firstIdx = state.shuffleIndices.first;
        await _playTrackAtIndex(firstIdx);
        return;
      }
    } else {
      if (state.currentIndex < state.queue.length - 1) {
        await _playTrackAtIndex(state.currentIndex + 1);
        return;
      } else if (state.repeatMode == AudioRepeatMode.all) {
        await _playTrackAtIndex(0);
        return;
      }
    }

    // End of queue reached with repeat off
    await _playerService.pause();
    await _playerService.seek(Duration.zero);
    state = state.copyWith(isPlaying: false, position: Duration.zero);
  }

  Future<void> previous() async {
    if (state.isEmpty) return;

    // Standard audio player convention: if played > 3 seconds, restart current track
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (state.isShuffleEnabled && state.shuffleIndices.isNotEmpty) {
      final currentPosInShuffle =
          state.shuffleIndices.indexOf(state.currentIndex);
      if (currentPosInShuffle > 0) {
        final prevIdx = state.shuffleIndices[currentPosInShuffle - 1];
        await _playTrackAtIndex(prevIdx);
        return;
      } else if (state.repeatMode == AudioRepeatMode.all) {
        final lastIdx = state.shuffleIndices.last;
        await _playTrackAtIndex(lastIdx);
        return;
      }
    } else {
      if (state.currentIndex > 0) {
        await _playTrackAtIndex(state.currentIndex - 1);
        return;
      } else if (state.repeatMode == AudioRepeatMode.all) {
        await _playTrackAtIndex(state.queue.length - 1);
        return;
      }
    }

    await seek(Duration.zero);
  }

  void _onTrackCompleted() {
    _consecutiveFailures = 0;
    if (_sleepTimerEndOfTrack) {
      _cancelSleepTimer();
      pause();
      return;
    }

    if (state.repeatMode == AudioRepeatMode.one) {
      seek(Duration.zero);
      play();
      return;
    }

    if (state.hasNext) {
      next();
    } else if (state.repeatMode == AudioRepeatMode.all) {
      next();
    } else {
      pause();
      seek(Duration.zero);
      _updateNotification();
    }
  }

  // --- Queue Actions ---

  Future<void> playNow(AudioTrackItem track, {String? playlistId}) async {
    final newItem = QueueItem(queueId: _generateQueueId(), track: track);
    final newQueue = List<QueueItem>.from(state.queue);

    final insertIndex = state.currentIndex >= 0 ? state.currentIndex + 1 : 0;
    newQueue.insert(insertIndex, newItem);

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, insertIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      currentIndex: insertIndex,
      shuffleIndices: shuffle,
      activePlaylistId: playlistId,
      clearActivePlaylist: playlistId == null,
    );

    await _playTrackAtIndex(insertIndex);
  }

  Future<void> playTrackList(
    List<AudioTrackItem> tracks, {
    int initialIndex = 0,
    String? playlistId,
  }) async {
    if (tracks.isEmpty) return;

    final newQueue = tracks
        .map((t) => QueueItem(queueId: _generateQueueId(), track: t))
        .toList();

    final safeIndex = (initialIndex >= 0 && initialIndex < newQueue.length)
        ? initialIndex
        : 0;

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, safeIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      currentIndex: safeIndex,
      shuffleIndices: shuffle,
      activePlaylistId: playlistId,
      clearActivePlaylist: playlistId == null,
    );

    await _playTrackAtIndex(safeIndex);
  }

  void updateTrackInfo(String id, {String? newTitle, String? newPath}) {
    bool changed = false;
    final updatedQueue = state.queue.map((item) {
      if (item.track.id == id) {
        changed = true;
        return QueueItem(
          queueId: item.queueId,
          track: item.track.copyWith(
            title: newTitle ?? item.track.title,
            path: newPath ?? item.track.path,
          ),
        );
      }
      return item;
    }).toList();

    if (changed) {
      state = state.copyWith(queue: updatedQueue);
      _saveQueue();
    }
  }

  Future<void> removeTrackById(String id) async {
    final item = state.queue.where((i) => i.track.id == id).firstOrNull;
    if (item != null) {
      await removeQueueItem(item.queueId);
    }
  }

  void playNext(AudioTrackItem track) {
    final newItem = QueueItem(queueId: _generateQueueId(), track: track);
    final newQueue = List<QueueItem>.from(state.queue);

    if (newQueue.isEmpty) {
      playNow(track);
      return;
    }

    final insertIndex = state.currentIndex + 1;
    newQueue.insert(insertIndex, newItem);

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, state.currentIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  void addTrack(AudioTrackItem track) {
    final newItem = QueueItem(queueId: _generateQueueId(), track: track);
    final newQueue = List<QueueItem>.from(state.queue)..add(newItem);

    if (state.queue.isEmpty) {
      playNow(track);
      return;
    }

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, state.currentIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  void addFolder(List<AudioTrackItem> tracks) {
    if (tracks.isEmpty) return;

    final newItems = tracks
        .map((t) => QueueItem(queueId: _generateQueueId(), track: t))
        .toList();

    final newQueue = List<QueueItem>.from(state.queue)..addAll(newItems);

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, state.currentIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  void addMultipleToQueue(List<AudioTrackItem> tracks) {
    addFolder(tracks);
  }

  Future<void> removeQueueItem(String queueId) async {
    final index = state.queue.indexWhere((item) => item.queueId == queueId);
    if (index == -1) return;

    final newQueue = List<QueueItem>.from(state.queue)..removeAt(index);

    if (newQueue.isEmpty) {
      await _playerService.stop();
      state = state.copyWith(
        queue: [],
        currentIndex: -1,
        shuffleIndices: [],
        isPlaying: false,
        position: Duration.zero,
        duration: Duration.zero,
      );
      _saveQueue();
      return;
    }

    int newIndex = state.currentIndex;
    if (index < state.currentIndex) {
      newIndex--;
    } else if (index == state.currentIndex) {
      if (newIndex >= newQueue.length) {
        newIndex = newQueue.length - 1;
      }
      List<int> shuffle = [];
      if (state.isShuffleEnabled) {
        shuffle = _buildShuffleIndices(newQueue.length, newIndex);
      }
      state = state.copyWith(
        queue: newQueue,
        currentIndex: newIndex,
        shuffleIndices: shuffle,
      );
      await _playTrackAtIndex(newIndex);
      return;
    }

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, newIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      currentIndex: newIndex,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= state.queue.length ||
        newIndex < 0 ||
        newIndex > state.queue.length) {
      return;
    }

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final newQueue = List<QueueItem>.from(state.queue);
    final movedItem = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, movedItem);

    int updatedCurrentIndex = state.currentIndex;
    if (state.currentIndex == oldIndex) {
      updatedCurrentIndex = newIndex;
    } else if (oldIndex < state.currentIndex && newIndex >= state.currentIndex) {
      updatedCurrentIndex--;
    } else if (oldIndex > state.currentIndex && newIndex <= state.currentIndex) {
      updatedCurrentIndex++;
    }

    List<int> shuffle = [];
    if (state.isShuffleEnabled) {
      shuffle = _buildShuffleIndices(newQueue.length, updatedCurrentIndex);
    }

    state = state.copyWith(
      queue: newQueue,
      currentIndex: updatedCurrentIndex,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  Future<void> clearQueue() async {
    await _playerService.stop();
    _playerService.stopNotification();
    state = state.copyWith(
      queue: [],
      currentIndex: -1,
      shuffleIndices: [],
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      clearError: true,
    );
    _saveQueue();
  }

  // --- Modes: Shuffle and Repeat ---

  void toggleShuffle() {
    final enable = !state.isShuffleEnabled;
    List<int> shuffle = [];
    if (enable && state.queue.isNotEmpty) {
      shuffle = _buildShuffleIndices(state.queue.length, state.currentIndex);
    }

    state = state.copyWith(
      isShuffleEnabled: enable,
      shuffleIndices: shuffle,
    );
    _saveQueue();
  }

  void cycleRepeatMode() {
    final nextMode = switch (state.repeatMode) {
      AudioRepeatMode.off => AudioRepeatMode.all,
      AudioRepeatMode.all => AudioRepeatMode.one,
      AudioRepeatMode.one => AudioRepeatMode.off,
    };

    state = state.copyWith(repeatMode: nextMode);
    _saveQueue();
  }

  // --- Sleep Timer ---

  void setSleepTimer(Duration? duration, {bool endOfTrack = false}) {
    _cancelSleepTimer();

    if (endOfTrack) {
      _sleepTimerEndOfTrack = true;
      return;
    }

    if (duration == null || duration <= Duration.zero) {
      return;
    }

    _sleepTimerDuration = duration;
    _sleepTimerEndTime = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      pause();
      _cancelSleepTimer();
    });
  }

  void cancelSleepTimer() {
    _cancelSleepTimer();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    _sleepTimerEndOfTrack = false;
    _sleepTimerDuration = null;
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _compSub?.cancel();
    _errSub?.cancel();
    _playerService.onPlayRequested = null;
    _playerService.onPauseRequested = null;
    _playerService.onToggleRequested = null;
    _playerService.onNextRequested = null;
    _playerService.onPreviousRequested = null;
    _playerService.onSeekRequested = null;
    _playerService.stopNotification();
    super.dispose();
  }
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerNotifier, AudioQueueState>((ref) {
  return AudioPlayerNotifier(
    ref.watch(audioPlayerServiceProvider),
    ref.watch(audioStorageServiceProvider),
  );
});

final recentlyPlayedAudioProvider = Provider<List<AudioTrackItem>>((ref) {
  // Watches queue state so it invalidates/updates when tracks play
  ref.watch(audioPlayerProvider);
  return ref.watch(audioPlayerProvider.notifier).recentlyPlayed;
});

class AudioSettingsNotifier extends StateNotifier<AudioSettings> {
  final AudioStorageService _storageService;

  AudioSettingsNotifier(this._storageService) : super(const AudioSettings()) {
    _load();
  }

  Future<void> _load() async {
    final s = await _storageService.loadSettings();
    state = s;
  }

  Future<void> updateSettings(AudioSettings settings) async {
    state = settings;
    await _storageService.saveSettings(settings);
  }

  Future<void> setPauseOnHeadsetDisconnect(bool val) async {
    final updated = state.copyWith(pauseOnHeadsetDisconnect: val);
    await updateSettings(updated);
  }

  Future<void> setDefaultShuffle(bool val) async {
    final updated = state.copyWith(defaultShuffle: val);
    await updateSettings(updated);
  }

  Future<void> setDefaultRepeatMode(AudioRepeatMode mode) async {
    final updated = state.copyWith(defaultRepeatMode: mode);
    await updateSettings(updated);
  }
}

final audioSettingsProvider =
    StateNotifierProvider<AudioSettingsNotifier, AudioSettings>((ref) {
  return AudioSettingsNotifier(ref.watch(audioStorageServiceProvider));
});
