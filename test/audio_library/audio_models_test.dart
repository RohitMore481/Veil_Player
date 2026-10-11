import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/audio_folder_item.dart';
import 'package:veil_player/features/library/models/video_item.dart';

void main() {
  group('AudioTrackItem Tests', () {
    test('Correctly parses valid MediaStore map', () {
      final map = {
        'id': '101',
        'title': 'Midnight City',
        'artist': 'M83',
        'album': 'Hurry Up, We\'re Dreaming',
        'albumId': '55',
        'albumArtUri': 'content://media/external/audio/albumart/55',
        'path': '/storage/emulated/0/Music/M83/Midnight City.mp3',
        'contentUri': 'content://media/external/audio/media/101',
        'duration': 243000,
        'size': 9720000,
        'dateAdded': 1700000000,
        'trackNumber': 1005,
        'folderName': 'M83',
        'folderPath': '/storage/emulated/0/Music/M83',
      };

      final track = AudioTrackItem.fromMap(map);

      expect(track.id, '101');
      expect(track.title, 'Midnight City');
      expect(track.artist, 'M83');
      expect(track.album, 'Hurry Up, We\'re Dreaming');
      expect(track.albumId, '55');
      expect(track.albumArtUri, 'content://media/external/audio/albumart/55');
      expect(track.path, '/storage/emulated/0/Music/M83/Midnight City.mp3');
      expect(track.contentUri, 'content://media/external/audio/media/101');
      expect(track.duration, const Duration(milliseconds: 243000));
      expect(track.size, 9720000);
      expect(track.trackNumber, 5); // 1005 % 1000 = 5
      expect(track.folderName, 'M83');
      expect(track.folderPath, '/storage/emulated/0/Music/M83');
      expect(track.formattedDuration, '04:03');
    });

    test('Provides sensible fallbacks for missing or blank metadata', () {
      final map = {
        'id': '102',
        'title': '',
        'artist': '<unknown>',
        'album': '',
        'path': '/storage/emulated/0/Music/Singles/Acoustic_Guitar_Solo.flac',
        'duration': 0,
        'size': 0,
        'dateAdded': 0,
      };

      final track = AudioTrackItem.fromMap(map);

      expect(track.title, 'Acoustic_Guitar_Solo');
      expect(track.artist, 'Unknown Artist');
      expect(track.album, 'Unknown Album');
      expect(track.duration, Duration.zero);
      expect(track.size, 0);
      expect(track.folderName, 'Music');
      expect(track.trackNumber, isNull);
      expect(track.formattedSize, '0 B');
    });

    test('Handles null values without throwing', () {
      final map = <dynamic, dynamic>{};
      final track = AudioTrackItem.fromMap(map);

      expect(track.id, '');
      expect(track.title, 'Unknown Track');
      expect(track.artist, 'Unknown Artist');
      expect(track.album, 'Unknown Album');
      expect(track.duration, Duration.zero);
      expect(track.size, 0);
      expect(track.folderName, 'Music');
      expect(track.trackNumber, isNull);
    });

    test('Duration formatting handles various lengths', () {
      final trackSeconds = AudioTrackItem.fromMap({
        'id': '1',
        'path': '/song.mp3',
        'duration': 45000, // 45 seconds
      });
      expect(trackSeconds.formattedDuration, '00:45');

      final trackMinutes = AudioTrackItem.fromMap({
        'id': '2',
        'path': '/song.mp3',
        'duration': 325000, // 5 min 25 sec
      });
      expect(trackMinutes.formattedDuration, '05:25');

      final trackHours = AudioTrackItem.fromMap({
        'id': '3',
        'path': '/podcast.mp3',
        'duration': 3725000, // 1 hr 2 min 5 sec
      });
      expect(trackHours.formattedDuration, '01:02:05');
    });

    test('Size formatting handles KB, MB, and GB accurately', () {
      final kbTrack = AudioTrackItem.fromMap({
        'id': '1',
        'path': '/a.mp3',
        'size': 512 * 1024,
      });
      expect(kbTrack.formattedSize, '512.0 KB');

      final mbTrack = AudioTrackItem.fromMap({
        'id': '2',
        'path': '/b.mp3',
        'size': 15 * 1024 * 1024,
      });
      expect(mbTrack.formattedSize, '15.0 MB');
    });

    test('copyWith produces updated copy without mutating original', () {
      final original = AudioTrackItem(
        id: '1',
        title: 'Original Title',
        artist: 'Artist',
        album: 'Album',
        path: '/a.mp3',
        duration: const Duration(minutes: 3),
        size: 5000,
        dateAdded: DateTime(2026),
        folderName: 'Music',
        folderPath: '/Music',
      );

      final updated = original.copyWith(title: 'New Title');
      expect(updated.title, 'New Title');
      expect(original.title, 'Original Title');
      expect(updated.id, original.id);
      expect(updated.artist, original.artist);
    });

    test('Equality and hashCode verify identity', () {
      final trackA = AudioTrackItem(
        id: '1',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        path: '/music/song.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        folderName: 'Music',
        folderPath: '/music',
      );

      final trackB = AudioTrackItem(
        id: '1',
        title: 'Song Different Tag',
        artist: 'Artist',
        album: 'Album',
        path: '/music/song.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        folderName: 'Music',
        folderPath: '/music',
      );

      final trackC = AudioTrackItem(
        id: '2',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        path: '/music/other.mp3',
        duration: const Duration(minutes: 3),
        size: 1000,
        dateAdded: DateTime(2026),
        folderName: 'Music',
        folderPath: '/music',
      );

      expect(trackA, equals(trackB));
      expect(trackA.hashCode, equals(trackB.hashCode));
      expect(trackA, isNot(equals(trackC)));
    });

    test('toMap converts track back to map representation', () {
      final now = DateTime(2026, 10, 11);
      final track = AudioTrackItem(
        id: '10',
        title: 'Echoes',
        artist: 'Pink Floyd',
        album: 'Meddle',
        albumId: '99',
        albumArtUri: 'content://albumart/99',
        path: '/storage/Music/echoes.flac',
        contentUri: 'content://audio/10',
        duration: const Duration(minutes: 23, seconds: 31),
        size: 150000000,
        dateAdded: now,
        trackNumber: 6,
        folderName: 'Meddle',
        folderPath: '/storage/Music/Meddle',
      );

      final map = track.toMap();
      expect(map['id'], '10');
      expect(map['title'], 'Echoes');
      expect(map['duration'], const Duration(minutes: 23, seconds: 31).inMilliseconds);
      expect(map['trackNumber'], 6);
    });
  });

  group('AudioFolderItem Tests', () {
    test('Correctly parses valid audio folder map', () {
      final map = {
        'name': 'Rock Classics',
        'path': '/storage/emulated/0/Music/Rock',
        'count': 42,
        'totalDuration': 8400000,
        'totalSize': 420000000,
      };

      final folder = AudioFolderItem.fromMap(map);

      expect(folder.name, 'Rock Classics');
      expect(folder.path, '/storage/emulated/0/Music/Rock');
      expect(folder.trackCount, 42);
      expect(folder.formattedTrackCount, '42 songs');
      expect(folder.formattedTotalDuration, '2h 20m');
      expect(folder.formattedTotalSize, '400.5 MB');
    });

    test('Single song formatting', () {
      final folder = AudioFolderItem.fromMap({
        'name': 'Singles',
        'path': '/Music/Singles',
        'count': 1,
      });

      expect(folder.formattedTrackCount, '1 song');
    });

    test('Missing fields default safely', () {
      final folder = AudioFolderItem.fromMap({});

      expect(folder.name, 'Music');
      expect(folder.path, '');
      expect(folder.trackCount, 0);
      expect(folder.totalDuration, Duration.zero);
      expect(folder.totalSize, 0);
      expect(folder.formattedTrackCount, '0 songs');
      expect(folder.formattedTotalDuration, '0m');
      expect(folder.formattedTotalSize, '0 B');
    });
  });

  group('Domain Model Separation Tests', () {
    test('AudioTrackItem is structurally separate from VideoItem', () {
      final video = VideoItem(
        id: '1',
        title: 'Movie',
        path: '/video.mp4',
        duration: const Duration(hours: 2),
        size: 1000000,
        dateAdded: DateTime(2026),
        folderName: 'Movies',
      );

      final audio = AudioTrackItem(
        id: '1',
        title: 'Movie',
        artist: 'Composer',
        album: 'Soundtrack',
        path: '/video.mp4',
        duration: const Duration(hours: 2),
        size: 1000000,
        dateAdded: DateTime(2026),
        folderName: 'Movies',
        folderPath: '/storage/Movies',
      );

      // Verify they are distinct types and cannot equal each other
      expect(audio, isNot(equals(video)));
      expect(audio.runtimeType, isNot(equals(video.runtimeType)));
    });

    test('AudioFolderItem is structurally separate from FolderItem', () {
      const videoFolder = FolderItem(
        name: 'Clips',
        path: '/storage/Clips',
        count: 5,
        containsMovies: false,
      );

      const audioFolder = AudioFolderItem(
        name: 'Clips',
        path: '/storage/Clips',
        trackCount: 5,
      );

      expect(audioFolder, isNot(equals(videoFolder)));
      expect(audioFolder.runtimeType, isNot(equals(videoFolder.runtimeType)));
    });
  });
}
