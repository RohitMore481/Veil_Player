import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_folder_item.dart';
import '../services/audio_storage_service.dart';
import 'audio_library_providers.dart';
import 'audio_player_provider.dart';

class AudioPinnedFoldersNotifier extends StateNotifier<List<String>> {
  final AudioStorageService _storageService;

  AudioPinnedFoldersNotifier(this._storageService) : super([]) {
    loadPinnedFolders();
  }

  Future<void> loadPinnedFolders() async {
    final list = await _storageService.loadPinnedFolders();
    state = list;
  }

  Future<void> togglePin(String folderPath) async {
    if (state.contains(folderPath)) {
      final updated = state.where((p) => p != folderPath).toList();
      state = updated;
      await _storageService.savePinnedFolders(updated);
    } else {
      final updated = [...state, folderPath];
      state = updated;
      await _storageService.savePinnedFolders(updated);
    }
  }

  bool isPinned(String folderPath) => state.contains(folderPath);

  Future<void> unpin(String folderPath) async {
    if (state.contains(folderPath)) {
      final updated = state.where((p) => p != folderPath).toList();
      state = updated;
      await _storageService.savePinnedFolders(updated);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex > state.length) {
      return;
    }

    var adjustedNewIndex = newIndex;
    if (oldIndex < adjustedNewIndex) {
      adjustedNewIndex -= 1;
    }

    final updated = List<String>.from(state);
    final item = updated.removeAt(oldIndex);
    updated.insert(adjustedNewIndex, item);

    state = updated;
    await _storageService.savePinnedFolders(updated);
  }
}

final audioPinnedFoldersProvider =
    StateNotifierProvider<AudioPinnedFoldersNotifier, List<String>>((ref) {
  return AudioPinnedFoldersNotifier(ref.watch(audioStorageServiceProvider));
});

final audioPinnedFolderItemsProvider =
    Provider<List<AudioFolderItem>>((ref) {
  final pinnedPaths = ref.watch(audioPinnedFoldersProvider);
  final allFoldersAsync = ref.watch(audioFoldersProvider);

  return allFoldersAsync.maybeWhen(
    data: (allFolders) {
      final map = {for (final f in allFolders) f.path: f};
      final List<AudioFolderItem> result = [];
      for (final p in pinnedPaths) {
        if (map.containsKey(p)) {
          result.add(map[p]!);
        } else {
          // Graceful fallback for folder path not yet indexed or renamed
          final name = p.split(RegExp(r'[/\\]')).last;
          if (name.isNotEmpty) {
            result.add(AudioFolderItem(
              name: name,
              path: p,
              trackCount: 0,
            ));
          }
        }
      }
      return result;
    },
    orElse: () => [],
  );
});
