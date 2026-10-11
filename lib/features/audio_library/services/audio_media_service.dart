import 'package:flutter/services.dart';

class AudioMediaService {
  static const _channel = MethodChannel('veil_player/media');

  Future<String> checkAudioPermission() async {
    try {
      final String result = await _channel.invokeMethod('checkAudioPermission');
      return result;
    } on PlatformException catch (_) {
      return 'denied';
    }
  }

  Future<String> requestAudioPermission() async {
    try {
      final String result = await _channel.invokeMethod('requestAudioPermission');
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

  Future<List<Map<dynamic, dynamic>>> getAudioTracks({
    required int limit,
    required int offset,
    String? folderName,
    String? folderPath,
  }) async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod(
        'getAudioTracks',
        {
          'limit': limit,
          'offset': offset,
          'folderName': folderName,
          'folderPath': folderPath,
        },
      );
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }

  Future<List<Map<dynamic, dynamic>>> getAudioFolders() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getAudioFolders');
      if (result == null) return [];
      return result.cast<Map<dynamic, dynamic>>();
    } on PlatformException catch (_) {
      return [];
    }
  }
}
