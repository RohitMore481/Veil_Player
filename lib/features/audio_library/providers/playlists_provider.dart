import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_item.dart';
import '../models/playlist.dart';
import '../services/audio_storage_service.dart';
import 'audio_player_provider.dart';

class PlaylistsNotifier extends StateNotifier<List<Playlist>> {
  final AudioStorageService _storageService;

  PlaylistsNotifier(this._storageService) : super([]) {
    loadPlaylists();
  }

  Future<void> loadPlaylists() async {
    final list = await _storageService.loadPlaylists();
    state = list;
  }

  Future<Playlist> createPlaylist(String name) async {
    final trimmedName = name.trim().isEmpty ? 'Untitled Playlist' : name.trim();
    final now = DateTime.now();
    final newPlaylist = Playlist(
      id: 'pl_${now.microsecondsSinceEpoch}_${state.length}',
      name: trimmedName,
      tracks: const [],
      createdAt: now,
      updatedAt: now,
    );

    final updated = [...state, newPlaylist];
    state = updated;
    await _storageService.savePlaylists(updated);
    return newPlaylist;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final trimmed = newName.trim().isEmpty ? 'Untitled Playlist' : newName.trim();
    final updated = state.map((p) {
      if (p.id == id) {
        return p.copyWith(name: trimmed, updatedAt: DateTime.now());
      }
      return p;
    }).toList();

    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Future<void> deletePlaylist(String id) async {
    final updated = state.where((p) => p.id != id).toList();
    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Future<void> addTrackToPlaylist(String playlistId, AudioTrackItem track) async {
    await addTracksToPlaylist(playlistId, [track]);
  }

  Future<void> addTracksToPlaylist(
      String playlistId, List<AudioTrackItem> newTracks) async {
    if (newTracks.isEmpty) return;

    final updated = state.map((p) {
      if (p.id == playlistId) {
        return p.copyWith(
          tracks: [...p.tracks, ...newTracks],
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();

    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Future<void> removeTrackFromPlaylist(String playlistId, int trackIndex) async {
    final updated = state.map((p) {
      if (p.id == playlistId) {
        if (trackIndex >= 0 && trackIndex < p.tracks.length) {
          final newTracks = List<AudioTrackItem>.from(p.tracks)
            ..removeAt(trackIndex);
          return p.copyWith(
            tracks: newTracks,
            updatedAt: DateTime.now(),
          );
        }
      }
      return p;
    }).toList();

    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Future<void> removeTrackFromAllPlaylists(String trackId) async {
    final updated = state.map((p) {
      final newTracks = p.tracks.where((t) => t.id != trackId).toList();
      return p.copyWith(tracks: newTracks, updatedAt: DateTime.now());
    }).toList();

    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Future<void> reorderTracks(
      String playlistId, int oldIndex, int newIndex) async {
    final updated = state.map((p) {
      if (p.id == playlistId) {
        if (oldIndex < 0 ||
            oldIndex >= p.tracks.length ||
            newIndex < 0 ||
            newIndex > p.tracks.length) {
          return p;
        }

        var adjustedNewIndex = newIndex;
        if (oldIndex < adjustedNewIndex) {
          adjustedNewIndex -= 1;
        }

        final newTracks = List<AudioTrackItem>.from(p.tracks);
        final item = newTracks.removeAt(oldIndex);
        newTracks.insert(adjustedNewIndex, item);

        return p.copyWith(
          tracks: newTracks,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();

    state = updated;
    await _storageService.savePlaylists(updated);
  }

  Playlist? getPlaylist(String id) {
    try {
      return state.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<Playlist>>((ref) {
  return PlaylistsNotifier(ref.watch(audioStorageServiceProvider));
});
