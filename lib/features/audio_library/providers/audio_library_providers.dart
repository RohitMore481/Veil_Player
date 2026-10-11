import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_item.dart';
import '../models/audio_folder_item.dart';
import '../repositories/audio_media_repository.dart';
import '../services/audio_media_service.dart';

final audioMediaServiceProvider = Provider<AudioMediaService>((ref) {
  return AudioMediaService();
});

final audioMediaRepositoryProvider = Provider<AudioMediaRepository>((ref) {
  return AudioMediaRepository(ref.watch(audioMediaServiceProvider));
});

// Audio Permission State Provider
class AudioPermissionNotifier extends StateNotifier<String> {
  final AudioMediaRepository _repository;

  AudioPermissionNotifier(this._repository) : super('checking') {
    checkPermission();
  }

  Future<void> checkPermission() async {
    final status = await _repository.checkAudioPermission();
    state = status;
  }

  Future<void> requestPermission() async {
    final status = await _repository.requestAudioPermission();
    state = status;
  }

  Future<void> openSettings() async {
    await _repository.openSettings();
    await checkPermission();
  }
}

final audioPermissionProvider = StateNotifierProvider<AudioPermissionNotifier, String>((ref) {
  return AudioPermissionNotifier(ref.watch(audioMediaRepositoryProvider));
});

// Audio Folders Provider
final audioFoldersProvider = FutureProvider<List<AudioFolderItem>>((ref) async {
  final permission = ref.watch(audioPermissionProvider);
  if (permission != 'granted' && permission != 'partial') {
    return [];
  }

  final folders = await ref.watch(audioMediaRepositoryProvider).getAudioFolders();
  return List<AudioFolderItem>.from(folders)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

// Paginated Audio State
class PaginatedAudioState {
  final List<AudioTrackItem> tracks;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final String? error;

  PaginatedAudioState({
    required this.tracks,
    required this.isLoading,
    required this.hasMore,
    required this.offset,
    this.error,
  });

  PaginatedAudioState copyWith({
    List<AudioTrackItem>? tracks,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    String? error,
  }) {
    return PaginatedAudioState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      error: error ?? this.error,
    );
  }
}

int naturalCompare(String a, String b) {
  final regex = RegExp(r'(\d+)|(\D+)');
  final matchesA = regex.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final matchesB = regex.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();

  for (int i = 0; i < matchesA.length && i < matchesB.length; i++) {
    final matchA = matchesA[i];
    final matchB = matchesB[i];

    final isDigitA = RegExp(r'^\d+$').hasMatch(matchA);
    final isDigitB = RegExp(r'^\d+$').hasMatch(matchB);

    if (isDigitA && isDigitB) {
      final valA = int.parse(matchA);
      final valB = int.parse(matchB);
      if (valA != valB) {
        return valA.compareTo(valB);
      }
    } else {
      final comp = matchA.compareTo(matchB);
      if (comp != 0) {
        return comp;
      }
    }
  }
  return matchesA.length.compareTo(matchesB.length);
}

int compareAudioTracks(AudioTrackItem a, AudioTrackItem b) {
  if (a.trackNumber != null && b.trackNumber != null && a.trackNumber != b.trackNumber) {
    return a.trackNumber!.compareTo(b.trackNumber!);
  }
  return naturalCompare(a.title, b.title);
}

// All Audio Tracks Notifier
class PaginatedAudioTracksNotifier extends StateNotifier<PaginatedAudioState> {
  final AudioMediaRepository _repository;
  static const _limit = 50;

  PaginatedAudioTracksNotifier(this._repository, {required bool hasPermission})
      : super(PaginatedAudioState(tracks: [], isLoading: false, hasMore: hasPermission, offset: 0)) {
    if (hasPermission) {
      loadNextPage();
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final newTracks = await _repository.getAudioTracks(
        limit: _limit,
        offset: state.offset,
      );
      final mergedTracks = [...state.tracks, ...newTracks];

      state = state.copyWith(
        tracks: mergedTracks,
        isLoading: false,
        hasMore: newTracks.length == _limit,
        offset: state.offset + newTracks.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    state = PaginatedAudioState(tracks: [], isLoading: false, hasMore: true, offset: 0);
    await loadNextPage();
  }
}

final allAudioTracksProvider = StateNotifierProvider<PaginatedAudioTracksNotifier, PaginatedAudioState>((ref) {
  final permission = ref.watch(audioPermissionProvider);
  final hasPermission = permission == 'granted' || permission == 'partial';
  return PaginatedAudioTracksNotifier(
    ref.watch(audioMediaRepositoryProvider),
    hasPermission: hasPermission,
  );
});

// Folder Audio Tracks Notifier (Scoped to folder path)
class FolderAudioTracksNotifier extends StateNotifier<PaginatedAudioState> {
  final AudioMediaRepository _repository;
  final String? _folderPath;
  static const _limit = 50;

  FolderAudioTracksNotifier(this._repository, this._folderPath, {required bool hasPermission})
      : super(PaginatedAudioState(tracks: [], isLoading: false, hasMore: hasPermission, offset: 0)) {
    if (hasPermission) {
      loadNextPage();
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final newTracks = await _repository.getAudioTracks(
        limit: _limit,
        offset: state.offset,
        folderPath: _folderPath,
      );
      final mergedTracks = [...state.tracks, ...newTracks];

      // Folder scoped tracks preserve album/track order or natural title sorting
      mergedTracks.sort(compareAudioTracks);

      state = state.copyWith(
        tracks: mergedTracks,
        isLoading: false,
        hasMore: newTracks.length == _limit,
        offset: state.offset + newTracks.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    state = PaginatedAudioState(tracks: [], isLoading: false, hasMore: true, offset: 0);
    await loadNextPage();
  }
}

final folderAudioTracksProvider =
    StateNotifierProvider.family<FolderAudioTracksNotifier, PaginatedAudioState, String?>(
  (ref, folderPath) {
    final permission = ref.watch(audioPermissionProvider);
    final hasPermission = permission == 'granted' || permission == 'partial';
    return FolderAudioTracksNotifier(
      ref.watch(audioMediaRepositoryProvider),
      folderPath,
      hasPermission: hasPermission,
    );
  },
);
