import 'package:flutter/services.dart';

class MediaService {
  static const _channel = MethodChannel('veil_player/media');

  Future<String> checkPermission() async {
    try {
      final String result = await _channel.invokeMethod('checkPermission');
      return result;
    } on PlatformException catch (_) {
      return 'denied';
    }
  }

  Future<String> requestPermission() async {
    try {
      final String result = await _channel.invokeMethod('requestPermission');
      return result;
    } on PlatformException catch (_) {
      return 'denied';
    }
  }

  Future<bool> openSettings() async {
    try {
      final bool result = await _channel.invokeMethod('openSettings');
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<List<Map<dynamic, dynamic>>> getVideos({
    required int limit,
    required int offset,
    String? folderName,
    String? folderPath,
  }) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getVideos', {
        'limit': limit,
        'offset': offset,
        'folderName': folderName,
        'folderPath': folderPath,
      });
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<List<Map<dynamic, dynamic>>> getFolders() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getFolders');
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<String?> generateThumbnail(String id, String path) async {
    try {
      final String? result = await _channel.invokeMethod('generateThumbnail', {
        'id': id,
        'path': path,
      });
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<bool> savePlaybackPosition({
    required String id,
    required int positionMs,
    required int durationMs,
    required String title,
    required String path,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('savePlaybackPosition', {
        'id': id,
        'position': positionMs,
        'duration': durationMs,
        'title': title,
        'path': path,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<Map<dynamic, dynamic>?> getPlaybackPosition(String id) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getPlaybackPosition',
        {'id': id},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<List<Map<dynamic, dynamic>>> getAllPlaybackPositions() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'getAllPlaybackPositions',
      );
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<bool> clearPlaybackPosition(String id) async {
    try {
      final bool result = await _channel.invokeMethod('clearPlaybackPosition', {
        'id': id,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<double> getVolume() async {
    try {
      final double? result = await _channel.invokeMethod('getVolume');
      return result ?? 0.5;
    } on PlatformException catch (_) {
      return 0.5;
    }
  }

  Future<bool> setVolume(double volume) async {
    try {
      final bool result = await _channel.invokeMethod('setVolume', {
        'volume': volume,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<double> getBrightness() async {
    try {
      final double? result = await _channel.invokeMethod('getBrightness');
      // If native returns negative, it means system default. Fallback to a standard middle value like 0.5.
      if (result == null || result < 0) return 0.5;
      return result;
    } on PlatformException catch (_) {
      return 0.5;
    }
  }

  Future<bool> setBrightness(double brightness) async {
    try {
      final bool result = await _channel.invokeMethod('setBrightness', {
        'brightness': brightness,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> savePlayerSetting(String key, dynamic value) async {
    try {
      final bool result = await _channel.invokeMethod('savePlayerSetting', {
        'key': key,
        'value': value,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<dynamic> getPlayerSetting(String key, String type) async {
    try {
      final dynamic result = await _channel.invokeMethod('getPlayerSetting', {
        'key': key,
        'type': type,
      });
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getAllPlayerSettings() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getAllPlayerSettings',
      );
      if (result == null) return {};
      return result.cast<String, dynamic>();
    } on PlatformException catch (_) {
      return {};
    }
  }

  Future<bool> requestAudioFocus() async {
    try {
      final bool? result = await _channel.invokeMethod('requestAudioFocus');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> abandonAudioFocus() async {
    try {
      await _channel.invokeMethod('abandonAudioFocus');
    } on PlatformException catch (_) {}
  }

  Future<String?> pickSubtitleFile() async {
    try {
      final String? result = await _channel.invokeMethod('pickSubtitleFile');
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<bool> setPipEnabled(
    bool enabled, {
    int numerator = 16,
    int denominator = 9,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('setPipEnabled', {
        'enabled': enabled,
        'numerator': numerator,
        'denominator': denominator,
      });
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> enterPip() async {
    try {
      final bool result = await _channel.invokeMethod('enterPip');
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<String?> saveScreenshotToGallery(Uint8List bytes, String title) async {
    try {
      final String? result = await _channel.invokeMethod(
        'saveScreenshotToGallery',
        {'bytes': bytes, 'title': title},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }

  Future<bool> openScreenshotFolder() async {
    try {
      final bool result = await _channel.invokeMethod('openScreenshotFolder');
      return result;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<List<Map<dynamic, dynamic>>> searchVideos(String query) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'searchVideos',
        {'query': query},
      );
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<bool> hideFolder(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('hideFolder', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> clearThumbnailCache() async {
    try {
      final bool? result = await _channel.invokeMethod('clearThumbnailCache');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> updateActiveMediaSession({
    required String title,
    required bool isPlaying,
    required int positionMs,
    required int durationMs,
  }) async {
    try {
      final bool? result = await _channel
          .invokeMethod('updateActiveMediaSession', {
            'title': title,
            'isPlaying': isPlaying,
            'position': positionMs,
            'duration': durationMs,
          });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
