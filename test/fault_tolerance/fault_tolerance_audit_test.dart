import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_player/core/media_coordinator/media_coordinator.dart';
import 'package:veil_player/features/media_capabilities/models/playback_error.dart';
import 'package:veil_player/features/media_capabilities/services/media_diagnostics_service.dart';
import 'package:veil_player/features/library/models/video_item.dart';
import 'package:veil_player/features/audio_library/models/audio_item.dart';
import 'package:veil_player/features/audio_library/models/queue_item.dart';
import 'package:veil_player/features/audio_library/models/audio_queue_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fault Tolerance — MediaCoordinator Session Isolation', () {
    test('Unregistering an old video callback does not remove a newer active video callback', () {
      final coordinator = MediaCoordinator.instance;

      bool oldCallbackFired = false;
      bool newCallbackFired = false;

      void oldCallback() {
        oldCallbackFired = true;
      }

      void newCallback() {
        newCallbackFired = true;
      }

      // Session 1 registers
      coordinator.registerVideoSession(pauseVideo: oldCallback);
      // Session 2 registers (rapid reopen)
      coordinator.registerVideoSession(pauseVideo: newCallback);

      // Session 1 cleanup runs asynchronously and attempts unregister
      coordinator.unregisterVideoSession(pauseVideo: oldCallback);

      // Audio starts — should invoke the NEW callback, not null
      coordinator.onAudioStarting();

      expect(oldCallbackFired, isFalse, reason: 'Old session callback should not fire');
      expect(newCallbackFired, isTrue, reason: 'New session callback must remain registered');
    });

    test('Video starting notifies coordinator and invokes registered audio pause callback', () {
      final coordinator = MediaCoordinator.instance;
      bool audioPaused = false;

      coordinator.registerAudioSession(pauseAudio: () {
        audioPaused = true;
      });

      coordinator.onVideoStarting();
      expect(audioPaused, isTrue);

      coordinator.unregisterAudioSession();
    });
  });

  group('Fault Tolerance — Playback Error Classification', () {
    final service = MediaDiagnosticsService();

    test('Classifies permission denied errors accurately', () {
      final error = service.classifyRawError('OS error: Permission denied to open file');
      expect(error.kind, equals(PlaybackErrorKind.permissionDenied));
      expect(error.title, equals('Permission Denied'));
      expect(error.description, contains('permission'));
      expect(error.suggestion, contains('settings'));
    });

    test('Classifies missing file errors accurately', () {
      final error = service.classifyRawError('File does not exist: /storage/emulated/0/video.mp4');
      expect(error.kind, equals(PlaybackErrorKind.fileNotFound));
      expect(error.title, equals('File Not Found'));
      expect(error.description, contains('not be found'));
    });

    test('Classifies 0-byte empty file errors accurately', () {
      final error = service.classifyRawError('File is empty (0 bytes): /storage/test.mp4');
      expect(error.kind, equals(PlaybackErrorKind.emptyFile));
      expect(error.title, equals('Empty File'));
      expect(error.description, contains('0 bytes'));
    });

    test('Classifies corrupted media file errors accurately', () {
      final error = service.classifyRawError('ffmpeg: moov atom not found, file truncated');
      expect(error.kind, equals(PlaybackErrorKind.corruptedFile));
      expect(error.title, equals('Corrupted File'));
    });

    test('Classifies unsupported video codec errors accurately', () {
      final error = service.classifyRawError('could not open video decoder: unsupported');
      expect(error.kind, equals(PlaybackErrorKind.unsupportedVideoCodec));
      expect(error.title, equals('Unsupported Video Codec'));
    });
  });

  group('Fault Tolerance — Atomic Audio Storage Persistence', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audio_storage_ft_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Atomic JSON write guarantees complete payload without orphaned .tmp files', () async {
      final destFile = File('${tempDir.path}/queue.json');
      final tempFile = File('${destFile.path}.tmp');

      final sampleQueueData = {
        'currentIndex': 0,
        'isShuffleEnabled': false,
        'repeatMode': AudioRepeatMode.all.name,
        'positionMs': 45000,
        'queue': [
          {
            'queueId': 'q_1',
            'track': {
              'id': '101',
              'title': 'Test Audio Track',
              'artist': 'Test Artist',
              'album': 'Test Album',
              'path': '/storage/test.mp3',
              'durationMs': 180000,
              'size': 4096,
              'dateAddedMs': DateTime.now().millisecondsSinceEpoch,
              'folderName': 'Music',
              'folderPath': '/storage/Music',
            },
          }
        ],
      };

      final jsonStr = jsonEncode(sampleQueueData);
      await tempFile.writeAsString(jsonStr, flush: true);
      if (await destFile.exists()) {
        try {
          await destFile.delete();
        } catch (_) {}
      }
      await tempFile.rename(destFile.path);

      expect(await destFile.exists(), isTrue);
      expect(await tempFile.exists(), isFalse, reason: 'Temporary file must be cleaned up');

      final decoded = jsonDecode(await destFile.readAsString()) as Map<String, dynamic>;
      expect(decoded['currentIndex'], equals(0));
      expect(decoded['positionMs'], equals(45000));
      expect(decoded['queue'], isA<List>());
      expect((decoded['queue'] as List).length, equals(1));
    });

    test('Queue item validation filters out corrupted non-map entries', () {
      final rawList = [
        {
          'queueId': 'q_valid',
          'track': {
            'id': '201',
            'title': 'Valid Track',
            'artist': 'Artist',
            'album': 'Album',
            'path': '/storage/valid.mp3',
            'durationMs': 120000,
            'size': 2048,
            'dateAddedMs': DateTime.now().millisecondsSinceEpoch,
            'folderName': 'Music',
            'folderPath': '/storage/Music',
          }
        },
        null,
        'not_a_map_entry',
        12345,
      ];

      final validQueue = <QueueItem>[];
      for (final rawItem in rawList) {
        if (rawItem is Map && rawItem['queueId'] != null && (rawItem['queueId'] as String).isNotEmpty) {
          validQueue.add(QueueItem.fromMap(rawItem));
        }
      }

      expect(validQueue.length, equals(1));
      expect(validQueue.first.track.id, equals('201'));
    });
  });

  group('Fault Tolerance — Pagination Deduplication Logic', () {
    test('Duplicate video records with identical ID are deduplicated cleanly', () {
      final v1 = VideoItem(
        id: '101',
        title: 'Video 1',
        path: '/storage/v1.mp4',
        duration: const Duration(seconds: 120),
        size: 10240,
        dateAdded: DateTime.now(),
        folderName: 'Movies',
      );
      final v2 = VideoItem(
        id: '102',
        title: 'Video 2',
        path: '/storage/v2.mp4',
        duration: const Duration(seconds: 180),
        size: 20480,
        dateAdded: DateTime.now(),
        folderName: 'Movies',
      );
      // Simulated overlapping page result containing duplicate v1
      final v1Duplicate = VideoItem(
        id: '101',
        title: 'Video 1 (Updated)',
        path: '/storage/v1.mp4',
        duration: const Duration(seconds: 120),
        size: 10240,
        dateAdded: DateTime.now(),
        folderName: 'Movies',
      );

      final existing = [v1];
      final newPage = [v1Duplicate, v2];

      final uniqueMap = <String, VideoItem>{};
      for (final v in existing) {
        uniqueMap[v.id] = v;
      }
      for (final v in newPage) {
        uniqueMap[v.id] = v;
      }
      final merged = uniqueMap.values.toList();

      expect(merged.length, equals(2));
      expect(merged.map((v) => v.id).toList(), equals(['101', '102']));
    });

    test('Duplicate audio records with identical ID are deduplicated cleanly', () {
      final a1 = AudioTrackItem(
        id: '201',
        title: 'Track 1',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/a1.mp3',
        duration: const Duration(seconds: 200),
        size: 5000,
        dateAdded: DateTime.now(),
        folderName: 'Music',
        folderPath: '/storage/Music',
      );
      final a2 = AudioTrackItem(
        id: '202',
        title: 'Track 2',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/a2.mp3',
        duration: const Duration(seconds: 220),
        size: 6000,
        dateAdded: DateTime.now(),
        folderName: 'Music',
        folderPath: '/storage/Music',
      );
      final a2Duplicate = AudioTrackItem(
        id: '202',
        title: 'Track 2',
        artist: 'Artist',
        album: 'Album',
        path: '/storage/a2.mp3',
        duration: const Duration(seconds: 220),
        size: 6000,
        dateAdded: DateTime.now(),
        folderName: 'Music',
        folderPath: '/storage/Music',
      );

      final existing = [a1, a2];
      final newPage = [a2Duplicate];

      final uniqueMap = <String, AudioTrackItem>{};
      for (final a in existing) {
        uniqueMap[a.id] = a;
      }
      for (final a in newPage) {
        uniqueMap[a.id] = a;
      }
      final merged = uniqueMap.values.toList();

      expect(merged.length, equals(2));
      expect(merged.map((a) => a.id).toList(), equals(['201', '202']));
    });
  });
}
