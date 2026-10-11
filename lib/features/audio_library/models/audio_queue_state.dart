import 'audio_item.dart';
import 'queue_item.dart';

enum AudioRepeatMode {
  off,
  all,
  one,
}

class AudioQueueState {
  final List<QueueItem> queue;
  final int currentIndex;
  final bool isShuffleEnabled;
  final List<int> shuffleIndices;
  final AudioRepeatMode repeatMode;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final String? errorMessage;
  final String? activePlaylistId;

  const AudioQueueState({
    this.queue = const [],
    this.currentIndex = -1,
    this.isShuffleEnabled = false,
    this.shuffleIndices = const [],
    this.repeatMode = AudioRepeatMode.off,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
    this.activePlaylistId,
  });

  bool get isEmpty => queue.isEmpty;
  bool get isNotEmpty => queue.isNotEmpty;

  QueueItem? get currentItem =>
      (currentIndex >= 0 && currentIndex < queue.length)
          ? queue[currentIndex]
          : null;

  AudioTrackItem? get currentTrack => currentItem?.track;

  bool get hasNext {
    if (queue.isEmpty) return false;
    if (repeatMode == AudioRepeatMode.all || repeatMode == AudioRepeatMode.one) {
      return true;
    }
    if (isShuffleEnabled) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      return currentPosInShuffle >= 0 && currentPosInShuffle < shuffleIndices.length - 1;
    }
    return currentIndex >= 0 && currentIndex < queue.length - 1;
  }

  bool get hasPrevious {
    if (queue.isEmpty) return false;
    if (position.inSeconds > 3) return true; // Can restart current track
    if (repeatMode == AudioRepeatMode.all) return true;
    if (isShuffleEnabled) {
      final currentPosInShuffle = shuffleIndices.indexOf(currentIndex);
      return currentPosInShuffle > 0;
    }
    return currentIndex > 0;
  }

  AudioQueueState copyWith({
    List<QueueItem>? queue,
    int? currentIndex,
    bool? isShuffleEnabled,
    List<int>? shuffleIndices,
    AudioRepeatMode? repeatMode,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    String? errorMessage,
    bool clearError = false,
    String? activePlaylistId,
    bool clearActivePlaylist = false,
  }) {
    return AudioQueueState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      shuffleIndices: shuffleIndices ?? this.shuffleIndices,
      repeatMode: repeatMode ?? this.repeatMode,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      activePlaylistId: clearActivePlaylist
          ? null
          : (activePlaylistId ?? this.activePlaylistId),
    );
  }
}
