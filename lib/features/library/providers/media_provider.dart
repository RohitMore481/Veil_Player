import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/video_item.dart';
import '../repositories/media_repository.dart';
import '../services/media_service.dart';
import '../../file_operations/providers/file_operation_provider.dart';
import '../../player/providers/player_settings_provider.dart';

final mediaServiceProvider = Provider<MediaService>((ref) {
  return MediaService();
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(
    ref.watch(mediaServiceProvider),
    ref.watch(fileOperationServiceProvider),
    ref.watch(permissionServiceProvider),
    ref.watch(mediaStoreServiceProvider),
  );
});

// Permission State Provider
class PermissionNotifier extends StateNotifier<String> {
  final MediaRepository _repository;

  PermissionNotifier(this._repository) : super('checking') {
    checkPermission();
  }

  Future<void> checkPermission() async {
    final status = await _repository.checkPermission();
    state = status;
  }

  Future<void> requestPermission() async {
    final status = await _repository.requestPermission();
    state = status;
  }

  Future<void> openSettings() async {
    await _repository.openSettings();
    // Re-check after returning from settings
    checkPermission();
  }
}

final permissionProvider = StateNotifierProvider<PermissionNotifier, String>((
  ref,
) {
  return PermissionNotifier(ref.watch(mediaRepositoryProvider));
});

// Pinned Folders persistent state notifier
class PinnedFoldersNotifier extends StateNotifier<List<String>> {
  final MediaRepository _repository;
  static const _key = 'pinned_folders';

  PinnedFoldersNotifier(this._repository) : super([]) {
    _loadPinnedFolders();
  }

  Future<void> _loadPinnedFolders() async {
    try {
      final value = await _repository.getPlayerSetting(_key, 'string');
      if (value is String && value.isNotEmpty) {
        state = value.split(',').where((p) => p.isNotEmpty).toList();
      }
    } catch (_) {}
  }

  Future<void> togglePin(String path) async {
    final updated = List<String>.from(state);
    if (updated.contains(path)) {
      updated.remove(path);
    } else {
      updated.add(path);
    }
    state = updated;
    await _repository.savePlayerSetting(_key, updated.join(','));
  }

  Future<void> updatePinnedFolder(String oldPath, String newPath) async {
    final updated = List<String>.from(state);
    final idx = updated.indexOf(oldPath);
    if (idx != -1) {
      updated[idx] = newPath;
      state = updated;
      await _repository.savePlayerSetting(_key, updated.join(','));
    }
  }

  bool isPinned(String path) {
    return state.contains(path);
  }
}

final pinnedFoldersProvider =
    StateNotifierProvider<PinnedFoldersNotifier, List<String>>((ref) {
      return PinnedFoldersNotifier(ref.watch(mediaRepositoryProvider));
    });

// Folders List Provider
final foldersProvider = FutureProvider<List<FolderItem>>((ref) async {
  // Only fetch folders if permission is granted or partial
  final permission = ref.watch(permissionProvider);
  if (permission != 'granted' && permission != 'partial') {
    return [];
  }

  final folders = await ref.watch(mediaRepositoryProvider).getFolders();
  final pinnedPaths = ref.watch(pinnedFoldersProvider);

  int getFolderPriority(FolderItem folder) {
    if (pinnedPaths.contains(folder.path)) {
      return 0; // Pinned always first
    }
    final nameLower = folder.name.toLowerCase();
    if (nameLower.contains('telegram')) return 1;
    if (nameLower.contains('whatsapp')) return 2;
    if (nameLower.contains('download')) return 3;
    if (nameLower.contains('camera') || nameLower.contains('dcim')) return 4;
    if (folder.containsMovies ||
        nameLower.contains('movie') ||
        nameLower.contains('film') ||
        nameLower.contains('cinema')) {
      return 5;
    }
    return 6;
  }

  return List<FolderItem>.from(folders)..sort((a, b) {
    final prioA = getFolderPriority(a);
    final prioB = getFolderPriority(b);
    if (prioA != prioB) {
      return prioA.compareTo(prioB);
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
});

// Playback History (Continue Watching) Provider
class PlaybackHistoryNotifier extends StateNotifier<List<PlaybackHistoryItem>> {
  final MediaRepository _repository;

  PlaybackHistoryNotifier(this._repository) : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final history = await _repository.getAllPlaybackPositions();
      state = history;
    } catch (e) {
      // ignore
    }
  }

  Future<void> savePosition({
    required String id,
    required int positionMs,
    required int durationMs,
    required String title,
    required String path,
  }) async {
    await _repository.savePlaybackPosition(
      id: id,
      positionMs: positionMs,
      durationMs: durationMs,
      title: title,
      path: path,
    );
    await loadHistory();
  }

  Future<void> clearHistoryItem(String id) async {
    await _repository.clearPlaybackPosition(id);
    await loadHistory();
  }
}

final playbackHistoryProvider =
    StateNotifierProvider<PlaybackHistoryNotifier, List<PlaybackHistoryItem>>((
      ref,
    ) {
      return PlaybackHistoryNotifier(ref.watch(mediaRepositoryProvider));
    });

// Paginated Videos State
class PaginatedVideoState {
  final List<VideoItem> videos;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final String? error;

  PaginatedVideoState({
    required this.videos,
    required this.isLoading,
    required this.hasMore,
    required this.offset,
    this.error,
  });

  PaginatedVideoState copyWith({
    List<VideoItem>? videos,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    String? error,
  }) {
    return PaginatedVideoState(
      videos: videos ?? this.videos,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      error: error ?? this.error,
    );
  }
}

// Paginated Videos Notifier for folders or all videos
class FolderVideosNotifier extends StateNotifier<PaginatedVideoState> {
  final MediaRepository _repository;
  final String? _folderName;
  static const _limit = 50;

  FolderVideosNotifier(
    this._repository,
    this._folderName, {
    required bool hasPermission,
  }) : super(
         PaginatedVideoState(
           videos: [],
           isLoading: false,
           hasMore: hasPermission,
           offset: 0,
         ),
       ) {
    if (hasPermission) {
      loadNextPage();
    }
  }

  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final newVideos = await _repository.getVideos(
        limit: _limit,
        offset: state.offset,
        folderName: _folderName,
      );
      final mergedVideos = [...state.videos, ...newVideos];

      if (_folderName != null) {
        mergedVideos.sort((a, b) => _naturalCompare(a.title, b.title));
      }

      state = state.copyWith(
        videos: mergedVideos,
        isLoading: false,
        hasMore: newVideos.length == _limit,
        offset: state.offset + newVideos.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final matchesA = regex
        .allMatches(a.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final matchesB = regex
        .allMatches(b.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();

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

  Future<void> refresh() async {
    state = PaginatedVideoState(
      videos: [],
      isLoading: false,
      hasMore: true,
      offset: 0,
    );
    await loadNextPage();
  }
}

// Family provider to load paginated videos inside a specific folder (or null for all videos)
final folderVideosProvider =
    StateNotifierProvider.family<
      FolderVideosNotifier,
      PaginatedVideoState,
      String?
    >((ref, folderName) {
      final permission = ref.watch(permissionProvider);
      final hasPermission = permission == 'granted' || permission == 'partial';
      return FolderVideosNotifier(
        ref.watch(mediaRepositoryProvider),
        folderName,
        hasPermission: hasPermission,
      );
    });

// Lazy Thumbnail Loader Provider
final videoThumbnailProvider = FutureProvider.autoDispose
    .family<String?, VideoItem>((ref, video) async {
      final settings = ref.watch(playerSettingsProvider);
      if (settings.batterySaverMode) {
        return null;
      }
      if (video.thumbnailPath != null) return video.thumbnailPath;
      final repository = ref.watch(mediaRepositoryProvider);
      return repository.getThumbnail(video.id, video.path);
    });

// Global Search Providers
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<VideoItem>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];
  final repository = ref.watch(mediaRepositoryProvider);
  return repository.searchVideos(query.trim());
});

// Storage Manager Provider — tracks whether MANAGE_EXTERNAL_STORAGE is granted.
// When true, file deletions bypass the Android system confirmation dialog.
class StorageManagerNotifier extends StateNotifier<bool> {
  final MediaRepository _repository;

  StorageManagerNotifier(this._repository) : super(false) {
    _check();
  }

  Future<void> _check() async {
    final granted = await _repository.isStorageManager();
    state = granted;
  }

  /// Opens the MANAGE_EXTERNAL_STORAGE settings page and waits for the result.
  Future<bool> request() async {
    final granted = await _repository.requestManageStoragePermission();
    state = granted;
    return granted;
  }

  Future<void> recheck() => _check();
}

final storageManagerProvider =
    StateNotifierProvider<StorageManagerNotifier, bool>((ref) {
      return StorageManagerNotifier(ref.watch(mediaRepositoryProvider));
    });
