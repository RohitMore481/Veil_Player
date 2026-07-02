import 'package:flutter/services.dart';

class PermissionService {
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

  Future<bool> hasSafPermission(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('hasSafPermission', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestSafPermission(String path) async {
    try {
      final bool? result = await _channel.invokeMethod('requestSafPermission', {
        'path': path,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> needsSystemConfirmationForWrite() async {
    try {
      final bool? result = await _channel.invokeMethod(
        'needsSystemConfirmationForWrite',
      );
      return result ?? true;
    } on PlatformException catch (_) {
      return true;
    }
  }

  Future<bool> isStorageManager() async {
    try {
      final bool? result = await _channel.invokeMethod('isStorageManager');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> requestManageStoragePermission() async {
    try {
      final bool? result = await _channel.invokeMethod(
        'requestManageStoragePermission',
      );
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
