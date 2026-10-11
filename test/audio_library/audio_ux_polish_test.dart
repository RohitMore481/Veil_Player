import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/audio_folder_item.dart';
import 'package:veil_player/features/audio_library/models/audio_queue_state.dart';
import 'package:veil_player/features/audio_library/models/queue_item.dart';
import 'package:veil_player/features/audio_library/providers/audio_library_providers.dart';
import 'package:veil_player/features/audio_library/services/audio_media_service.dart';
import 'package:veil_player/features/audio_library/repositories/audio_media_repository.dart';

class _MockAllAudioTracksNotifier extends PaginatedAudioTracksNotifier {
  _MockAllAudioTracksNotifier([int count = 0])
      : super(AudioMediaRepository(AudioMediaService()), hasPermission: false) {
    state = state.copyWith(
      tracks: List.generate(
        count,
        (i) => AudioTrackItem(
          id: '$i',
          title: 'T$i',
          artist: 'A',
          album: 'Al',
          duration: Duration.zero,
          path: '/p/$i',
          size: 0,
          dateAdded: DateTime(2026),
          folderName: 'F',
          folderPath: '/p',
        ),
      ),
    );
  }
}

void main() {
  group('Audio UX Polish & Library Counters Tests', () {
    test('AudioFolderItem formattedTrackCount formats correctly', () {
      const folderSingle = AudioFolderItem(
        path: '/storage/emulated/0/Music',
        name: 'Music',
        trackCount: 1,
      );
      expect(folderSingle.formattedTrackCount, '1 song');

      const folderMultiple = AudioFolderItem(
        path: '/storage/emulated/0/Download',
        name: 'Download',
        trackCount: 42,
      );
      expect(folderMultiple.formattedTrackCount, '42 songs');

      const folderEmpty = AudioFolderItem(
        path: '/storage/emulated/0/Empty',
        name: 'Empty',
        trackCount: 0,
      );
      expect(folderEmpty.formattedTrackCount, '0 songs');
    });

    test('totalAudioTracksCountProvider sums folder track counts without duplication', () async {
      final container = ProviderContainer(
        overrides: [
          audioFoldersProvider.overrideWith((ref) => Future.value([
                const AudioFolderItem(
                  path: '/storage/emulated/0/Music',
                  name: 'Music',
                  trackCount: 15,
                ),
                const AudioFolderItem(
                  path: '/storage/emulated/0/Download',
                  name: 'Download',
                  trackCount: 25,
                ),
                const AudioFolderItem(
                  path: '/storage/emulated/0/Recordings',
                  name: 'Recordings',
                  trackCount: 5,
                ),
              ])),
          allAudioTracksProvider.overrideWith((ref) => _MockAllAudioTracksNotifier(0)),
        ],
      );

      await container.read(audioFoldersProvider.future);

      final total = container.read(totalAudioTracksCountProvider);
      expect(total, 45);
    });

    test('totalAudioTracksCountProvider returns 0 when folders list is empty or loading', () async {
      final container = ProviderContainer(
        overrides: [
          audioFoldersProvider.overrideWith((ref) => Future.value(<AudioFolderItem>[])),
          allAudioTracksProvider.overrideWith((ref) => _MockAllAudioTracksNotifier(0)),
        ],
      );

      await container.read(audioFoldersProvider.future);

      final total = container.read(totalAudioTracksCountProvider);
      expect(total, 0);
    });

    test('Only currently playing track is identified as active in list', () {
      final track1 = AudioTrackItem(
        id: 'track_1',
        title: 'Song 1',
        artist: 'Artist A',
        album: 'Album X',
        duration: const Duration(minutes: 3),
        path: '/storage/music/song1.mp3',
        size: 5000000,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(1600000000000),
        folderName: 'Music',
        folderPath: '/storage/music',
      );

      final track2 = AudioTrackItem(
        id: 'track_2',
        title: 'Song 2',
        artist: 'Artist B',
        album: 'Album Y',
        duration: const Duration(minutes: 4),
        path: '/storage/music/song2.mp3',
        size: 6000000,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(1600000100000),
        folderName: 'Music',
        folderPath: '/storage/music',
      );

      final queue = [
        QueueItem(queueId: 'q_1', track: track1),
        QueueItem(queueId: 'q_2', track: track2),
      ];

      // Playing track 1
      final statePlaying1 = AudioQueueState(
        queue: queue,
        currentIndex: 0,
        isPlaying: true,
      );

      expect(statePlaying1.currentTrack?.id, equals(track1.id));
      expect(statePlaying1.currentTrack?.id == track1.id, isTrue);
      expect(statePlaying1.currentTrack?.id == track2.id, isFalse);

      // Advance to track 2
      final statePlaying2 = AudioQueueState(
        queue: queue,
        currentIndex: 1,
        isPlaying: true,
      );

      expect(statePlaying2.currentTrack?.id, equals(track2.id));
      expect(statePlaying2.currentTrack?.id == track1.id, isFalse);
      expect(statePlaying2.currentTrack?.id == track2.id, isTrue);
    });

    test('Search filter matches against title, artist, and album case-insensitively', () {
      final tracks = [
        AudioTrackItem(
          id: '1',
          title: 'Midnight Echoes',
          artist: 'Luna Eclipse',
          album: 'Cosmic Dreams',
          duration: const Duration(minutes: 3),
          path: '/m/1.mp3',
          size: 1000,
          dateAdded: DateTime.fromMillisecondsSinceEpoch(1000),
          folderName: 'Music',
          folderPath: '/m',
        ),
        AudioTrackItem(
          id: '2',
          title: 'Solar Flare',
          artist: 'Astro',
          album: 'Sunlight',
          duration: const Duration(minutes: 3, seconds: 20),
          path: '/m/2.mp3',
          size: 1000,
          dateAdded: DateTime.fromMillisecondsSinceEpoch(2000),
          folderName: 'Music',
          folderPath: '/m',
        ),
        AudioTrackItem(
          id: '3',
          title: 'Starlight Odyssey',
          artist: 'Luna Eclipse',
          album: 'Deep Space',
          duration: const Duration(minutes: 4),
          path: '/m/3.mp3',
          size: 1000,
          dateAdded: DateTime.fromMillisecondsSinceEpoch(3000),
          folderName: 'Downloads',
          folderPath: '/m',
        ),
      ];

      // Filter by artist "luna"
      final byArtist = tracks.where((t) {
        final q = 'luna';
        return t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.album.toLowerCase().contains(q);
      }).toList();
      expect(byArtist.length, 2);

      // Filter by album "sunlight"
      final byAlbum = tracks.where((t) {
        final q = 'sunlight';
        return t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.album.toLowerCase().contains(q);
      }).toList();
      expect(byAlbum.length, 1);
      expect(byAlbum.first.id, '2');

      // Filter non-matching
      final byNonMatch = tracks.where((t) {
        final q = 'nonexistent';
        return t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.album.toLowerCase().contains(q);
      }).toList();
      expect(byNonMatch, isEmpty);
    });
  });
}
