import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/playlist.dart';
import 'package:veil_player/features/audio_library/providers/audio_pinned_folders_provider.dart';
import 'package:veil_player/features/audio_library/providers/playlists_provider.dart';
import 'package:veil_player/features/audio_library/services/audio_storage_service.dart';

AudioTrackItem createTestTrack({
  required String id,
  required String title,
  String artist = 'Test Artist',
  int durationMs = 180000,
}) {
  return AudioTrackItem(
    id: id,
    title: title,
    artist: artist,
    album: 'Test Album',
    path: '/music/$title.mp3',
    contentUri: 'content://media/external/audio/media/$id',
    duration: Duration(milliseconds: durationMs),
    size: 4096000,
    dateAdded: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    folderName: 'Music',
    folderPath: '/music',
  );
}

class FakeAudioStorageServiceWithPlaylists extends AudioStorageService {
  List<Playlist> savedPlaylists = [];
  List<String> savedPinnedFolders = [];

  @override
  Future<void> savePlaylists(List<Playlist> playlists) async {
    savedPlaylists = List.from(playlists);
  }

  @override
  Future<List<Playlist>> loadPlaylists() async {
    return List.from(savedPlaylists);
  }

  @override
  Future<void> savePinnedFolders(List<String> folderPaths) async {
    savedPinnedFolders = List.from(folderPaths);
  }

  @override
  Future<List<String>> loadPinnedFolders() async {
    return List.from(savedPinnedFolders);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playlist Model Tests', () {
    test('Playlist creation and formatting calculations', () {
      final t1 = createTestTrack(id: '1', title: 'Track 1', durationMs: 120000); // 2 min
      final t2 = createTestTrack(id: '2', title: 'Track 2', durationMs: 180000); // 3 min

      final playlist = Playlist(
        id: 'pl_1',
        name: 'Chill Vibes',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        tracks: [t1, t2],
      );

      expect(playlist.trackCount, 2);
      expect(playlist.formattedTrackCount, '2 songs');
      expect(playlist.totalDuration, const Duration(minutes: 5));
      expect(playlist.formattedTotalDuration, '5m');
    });

    test('Playlist JSON serialization and deserialization', () {
      final t1 = createTestTrack(id: '10', title: 'Midnight City');
      final original = Playlist(
        id: 'pl_test',
        name: 'Favorites',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000010000),
        tracks: [t1],
      );

      final json = original.toJson();
      final restored = Playlist.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.tracks.length, 1);
      expect(restored.tracks.first.title, 'Midnight City');
      expect(restored.createdAt, original.createdAt);
    });

    test('Playlist duplicate track additions retain individual occurrences', () {
      final t1 = createTestTrack(id: '1', title: 'Track A');
      final playlist = Playlist(
        id: 'pl_dup',
        name: 'Repeats',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        tracks: [t1, t1], // Intentionally identical track added twice
      );

      expect(playlist.tracks.length, 2);
      expect(playlist.tracks[0].id, '1');
      expect(playlist.tracks[1].id, '1');
    });
  });

  group('PlaylistsNotifier CRUD & Reordering Tests', () {
    late FakeAudioStorageServiceWithPlaylists fakeStorage;
    late PlaylistsNotifier notifier;

    setUp(() {
      fakeStorage = FakeAudioStorageServiceWithPlaylists();
      notifier = PlaylistsNotifier(fakeStorage);
    });

    test('Create playlist adds to list and persists', () async {
      final created = await notifier.createPlaylist('Gym Workout');

      expect(created.name, 'Gym Workout');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.name, 'Gym Workout');
      expect(fakeStorage.savedPlaylists.length, 1);
      expect(fakeStorage.savedPlaylists.first.name, 'Gym Workout');
    });

    test('Rename playlist updates name and persists', () async {
      final pl = await notifier.createPlaylist('Old Name');
      await notifier.renamePlaylist(pl.id, 'New Name');

      expect(notifier.state.first.name, 'New Name');
      expect(fakeStorage.savedPlaylists.first.name, 'New Name');
    });

    test('Delete playlist removes it without throwing', () async {
      final pl1 = await notifier.createPlaylist('List 1');
      final pl2 = await notifier.createPlaylist('List 2');
      expect(notifier.state.length, 2);

      await notifier.deletePlaylist(pl1.id);

      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, pl2.id);
      expect(fakeStorage.savedPlaylists.length, 1);
    });

    test('Add single and multiple tracks to playlist', () async {
      final pl = await notifier.createPlaylist('Roadtrip');
      final t1 = createTestTrack(id: '1', title: 'Highway to Hell');
      final t2 = createTestTrack(id: '2', title: 'Radar Love');

      await notifier.addTrackToPlaylist(pl.id, t1);
      expect(notifier.state.first.tracks.length, 1);
      expect(notifier.state.first.tracks.first.title, 'Highway to Hell');

      await notifier.addTracksToPlaylist(pl.id, [t2]);
      expect(notifier.state.first.tracks.length, 2);
      expect(notifier.state.first.tracks[1].title, 'Radar Love');
      expect(fakeStorage.savedPlaylists.first.tracks.length, 2);
    });

    test('Remove track from playlist removes only target index', () async {
      final pl = await notifier.createPlaylist('Party');
      final t1 = createTestTrack(id: '1', title: 'Track 1');
      final t2 = createTestTrack(id: '2', title: 'Track 2');
      final t3 = createTestTrack(id: '3', title: 'Track 3');

      await notifier.addTracksToPlaylist(pl.id, [t1, t2, t3]);
      expect(notifier.state.first.tracks.length, 3);

      // Remove t2 at index 1
      await notifier.removeTrackFromPlaylist(pl.id, 1);

      expect(notifier.state.first.tracks.length, 2);
      expect(notifier.state.first.tracks[0].title, 'Track 1');
      expect(notifier.state.first.tracks[1].title, 'Track 3');
      expect(fakeStorage.savedPlaylists.first.tracks.length, 2);
    });

    test('Reorder tracks within playlist', () async {
      final pl = await notifier.createPlaylist('Reorder Test');
      final t1 = createTestTrack(id: '1', title: 'A');
      final t2 = createTestTrack(id: '2', title: 'B');
      final t3 = createTestTrack(id: '3', title: 'C');

      await notifier.addTracksToPlaylist(pl.id, [t1, t2, t3]);

      // Move A (0) to after C (position 3 in ReorderableListView semantics)
      await notifier.reorderTracks(pl.id, 0, 3);

      final reordered = notifier.state.first.tracks;
      expect(reordered[0].title, 'B');
      expect(reordered[1].title, 'C');
      expect(reordered[2].title, 'A');
      expect(fakeStorage.savedPlaylists.first.tracks[2].title, 'A');
    });
  });

  group('Audio Pinned Folders Tests', () {
    late FakeAudioStorageServiceWithPlaylists fakeStorage;
    late AudioPinnedFoldersNotifier notifier;

    setUp(() {
      fakeStorage = FakeAudioStorageServiceWithPlaylists();
      notifier = AudioPinnedFoldersNotifier(fakeStorage);
    });

    test('Pin and unpin folder toggles state and persists', () async {
      expect(notifier.isPinned('/storage/Music/Rock'), isFalse);

      await notifier.togglePin('/storage/Music/Rock');
      expect(notifier.isPinned('/storage/Music/Rock'), isTrue);
      expect(fakeStorage.savedPinnedFolders.contains('/storage/Music/Rock'), isTrue);

      await notifier.togglePin('/storage/Music/Rock');
      expect(notifier.isPinned('/storage/Music/Rock'), isFalse);
      expect(fakeStorage.savedPinnedFolders.contains('/storage/Music/Rock'), isFalse);
    });

    test('Reorder pinned folders adjusts indices', () async {
      await notifier.togglePin('/storage/FolderA');
      await notifier.togglePin('/storage/FolderB');
      await notifier.togglePin('/storage/FolderC');

      expect(notifier.state, ['/storage/FolderA', '/storage/FolderB', '/storage/FolderC']);

      // Move FolderA (0) to end (index 3)
      await notifier.reorder(0, 3);

      expect(notifier.state, ['/storage/FolderB', '/storage/FolderC', '/storage/FolderA']);
      expect(fakeStorage.savedPinnedFolders, ['/storage/FolderB', '/storage/FolderC', '/storage/FolderA']);
    });
  });
}
