import 'package:flutter/services.dart';

class MediaStoreService {
  static const _channel = MethodChannel('veil_player/media');

  Future<bool> refreshFolder(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('refreshFolder', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> shareVideo(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('shareVideo', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<Map<dynamic, dynamic>?> getVideoMetadata(String path) async {
    try {
      final Map<dynamic, dynamic>? result = await _channel.invokeMethod(
        'getVideoMetadata',
        {'path': path},
      );
      return result;
    } on PlatformException catch (_) {
      return null;
    }
  }
}
