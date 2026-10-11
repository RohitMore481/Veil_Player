import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../models/audio_item.dart';
import '../models/audio_queue_state.dart';
import '../models/audio_settings.dart';
import '../models/playlist.dart';
import '../models/queue_item.dart';

class AudioStorageService {
  static const _channel = MethodChannel('veil_player/media');
  Directory? _audioDir;

  Future<Directory> _getAudioDir() async {
    if (_audioDir != null) return _audioDir!;
    String? basePath;
    try {
      basePath = await _channel.invokeMethod<String>('getAppPrivateDirectory');
    } catch (_) {}

    basePath ??= Directory.systemTemp.path;
    final dir = Directory('$basePath/veil_audio');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _audioDir = dir;
    return dir;
  }

  // --- Queue State Persistence ---

  Future<void> saveQueueState({
    required List<QueueItem> queue,
    required int currentIndex,
    required bool isShuffleEnabled,
    required AudioRepeatMode repeatMode,
    required Duration position,
  }) async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/queue.json');
      final data = {
        'currentIndex': currentIndex,
        'isShuffleEnabled': isShuffleEnabled,
        'repeatMode': repeatMode.name,
        'positionMs': position.inMilliseconds,
        'queue': queue.map((item) => item.toMap()).toList(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadQueueState() async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/queue.json');
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;

      final rawQueue = decoded['queue'] as List<dynamic>? ?? [];
      final List<QueueItem> validQueue = [];

      for (final rawItem in rawQueue) {
        if (rawItem is Map) {
          final item = QueueItem.fromMap(rawItem);
          // Only keep tracks whose file path exists (if accessible)
          if (item.track.path.isNotEmpty) {
            try {
              if (File(item.track.path).existsSync()) {
                validQueue.add(item);
                continue;
              }
            } catch (_) {
              // On permissions edge cases, retain the track reference
              validQueue.add(item);
              continue;
            }
          }
          validQueue.add(item);
        }
      }

      int currentIndex = decoded['currentIndex'] as int? ?? -1;
      if (currentIndex >= validQueue.length) {
        currentIndex = validQueue.isNotEmpty ? 0 : -1;
      }

      final isShuffle = decoded['isShuffleEnabled'] as bool? ?? false;
      final repeatName = decoded['repeatMode'] as String? ?? 'off';
      final repeatMode = AudioRepeatMode.values.firstWhere(
        (m) => m.name == repeatName,
        orElse: () => AudioRepeatMode.off,
      );
      final positionMs = decoded['positionMs'] as int? ?? 0;

      return {
        'queue': validQueue,
        'currentIndex': currentIndex,
        'isShuffleEnabled': isShuffle,
        'repeatMode': repeatMode,
        'position': Duration(milliseconds: positionMs),
      };
    } catch (_) {
      return null;
    }
  }

  // --- Recently Played Tracks Persistence ---

  Future<void> saveRecentlyPlayed(List<AudioTrackItem> tracks) async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/recently_played.json');
      final list = tracks.take(50).map((t) => t.toMap()).toList();
      await file.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  Future<List<AudioTrackItem>> loadRecentlyPlayed() async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/recently_played.json');
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as List<dynamic>;
      final List<AudioTrackItem> list = [];

      for (final raw in decoded) {
        if (raw is Map) {
          list.add(AudioTrackItem.fromMap(raw));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  // --- Audio Settings Persistence ---

  Future<void> saveSettings(AudioSettings settings) async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/audio_settings.json');
      await file.writeAsString(jsonEncode(settings.toMap()), flush: true);
    } catch (_) {}
  }

  Future<AudioSettings> loadSettings() async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/audio_settings.json');
      if (!await file.exists()) return const AudioSettings();

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return AudioSettings.fromMap(decoded);
    } catch (_) {
      return const AudioSettings();
    }
  }

  // --- Playlists Persistence ---

  Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/playlists.json');
      final list = playlists.map((p) => p.toMap()).toList();
      await file.writeAsString(jsonEncode(list), flush: true);
    } catch (_) {}
  }

  Future<List<Playlist>> loadPlaylists() async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/playlists.json');
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as List<dynamic>;
      final List<Playlist> list = [];

      for (final raw in decoded) {
        if (raw is Map) {
          list.add(Playlist.fromMap(raw));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  // --- Audio Pinned Folders Persistence ---

  Future<void> savePinnedFolders(List<String> paths) async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/pinned_folders.json');
      await file.writeAsString(jsonEncode(paths), flush: true);
    } catch (_) {}
  }

  Future<List<String>> loadPinnedFolders() async {
    try {
      final dir = await _getAudioDir();
      final file = File('${dir.path}/pinned_folders.json');
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as List<dynamic>;
      return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }
}
