import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/audio_folder_item.dart';
import 'package:veil_player/features/audio_library/providers/audio_library_providers.dart';

void main() {
  group('Audio Natural Sorting Tests', () {
    test('naturalCompare sorts numeric titles properly', () {
      final titles = ['Track 10', 'Track 2', 'Track 1', 'Track 20', 'Track 3'];
      titles.sort(naturalCompare);

      expect(titles, ['Track 1', 'Track 2', 'Track 3', 'Track 10', 'Track 20']);
    });

    test('naturalCompare handles mixed alphanumerics and casing', () {
      final list = ['song_B', 'Song_a', 'song_1', 'song_10', 'song_2'];
      list.sort(naturalCompare);

      expect(list, ['song_1', 'song_2', 'song_10', 'Song_a', 'song_B']);
    });

    test('compareAudioTracks prioritizes track number if both tracks have it', () {
      final track1 = AudioTrackItem(
        id: '1',
        title: 'Zebra Song',
        artist: 'Artist',
        album: 'Album',
        path: '/Music/zebra.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        trackNumber: 1,
        folderName: 'Album',
        folderPath: '/Music',
      );

      final track2 = AudioTrackItem(
        id: '2',
        title: 'Apple Song',
        artist: 'Artist',
        album: 'Album',
        path: '/Music/apple.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        trackNumber: 2,
        folderName: 'Album',
        folderPath: '/Music',
      );

      final tracks = [track2, track1];
      tracks.sort(compareAudioTracks);

      expect(tracks.first.title, 'Zebra Song'); // track 1 before track 2
      expect(tracks.last.title, 'Apple Song');
    });

    test('compareAudioTracks falls back to natural title sort when track numbers are absent', () {
      final trackA = AudioTrackItem(
        id: '1',
        title: 'Track 10',
        artist: 'Artist',
        album: 'Album',
        path: '/Music/10.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        folderName: 'Album',
        folderPath: '/Music',
      );

      final trackB = AudioTrackItem(
        id: '2',
        title: 'Track 2',
        artist: 'Artist',
        album: 'Album',
        path: '/Music/2.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        folderName: 'Album',
        folderPath: '/Music',
      );

      final tracks = [trackA, trackB];
      tracks.sort(compareAudioTracks);

      expect(tracks.first.title, 'Track 2');
      expect(tracks.last.title, 'Track 10');
    });
  });

  group('Duplicate Filenames in Different Folders Tests', () {
    test('Differentiates identical filenames by media ID and folder path', () {
      final trackFolderA = AudioTrackItem.fromMap({
        'id': '2001',
        'title': 'Track 01',
        'artist': 'Artist A',
        'album': 'Album One',
        'path': '/storage/emulated/0/Music/AlbumA/track01.mp3',
        'duration': 180000,
        'size': 5000000,
        'folderName': 'AlbumA',
        'folderPath': '/storage/emulated/0/Music/AlbumA',
      });

      final trackFolderB = AudioTrackItem.fromMap({
        'id': '2002',
        'title': 'Track 01',
        'artist': 'Artist B',
        'album': 'Album Two',
        'path': '/storage/emulated/0/Music/AlbumB/track01.mp3',
        'duration': 210000,
        'size': 6000000,
        'folderName': 'AlbumB',
        'folderPath': '/storage/emulated/0/Music/AlbumB',
      });

      expect(trackFolderA.id, isNot(equals(trackFolderB.id)));
      expect(trackFolderA.path, isNot(equals(trackFolderB.path)));
      expect(trackFolderA.folderPath, '/storage/emulated/0/Music/AlbumA');
      expect(trackFolderB.folderPath, '/storage/emulated/0/Music/AlbumB');
      expect(trackFolderA == trackFolderB, isFalse);
    });
  });

  group('Empty and Malformed Result Handling Tests', () {
    test('Empty raw list returns empty parsed models list', () {
      final rawList = <Map<dynamic, dynamic>>[];
      final tracks = rawList.map((m) => AudioTrackItem.fromMap(m)).toList();
      final folders = rawList.map((m) => AudioFolderItem.fromMap(m)).toList();

      expect(tracks, isEmpty);
      expect(folders, isEmpty);
    });

    test('Malformed and partial map entries are handled gracefully', () {
      final malformedList = [
        {'id': null, 'path': null},
        {'id': 123, 'title': null, 'duration': 'invalid_string'},
        {'id': '456', 'size': -500, 'duration': -1000},
      ];

      final tracks = malformedList.map((m) => AudioTrackItem.fromMap(m)).toList();
      expect(tracks.length, 3);
      expect(tracks[0].title, 'Unknown Track');
      expect(tracks[0].duration, Duration.zero);
      expect(tracks[1].id, '123');
      expect(tracks[1].duration, Duration.zero);
      expect(tracks[2].size, 0); // negative clamped to 0
      expect(tracks[2].duration, Duration.zero); // negative clamped to zero
    });
  });
}
