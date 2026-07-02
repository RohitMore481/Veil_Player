import 'package:flutter/services.dart';

enum FileOpResult { success, safPermissionRequired, cancelled, error }

class FileOperationService {
  static const _channel = MethodChannel('veil_player/media');

  Future<FileOpResult> renameVideo(
    String id,
    String path,
    String newName,
  ) async {
    try {
      final String? result = await _channel.invokeMethod('renameVideo', {
        'id': id,
        'path': path,
        'newName': newName,
      });
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> deleteVideo(String id, String path) async {
    try {
      final String? result = await _channel.invokeMethod('deleteVideo', {
        'id': id,
        'path': path,
      });
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> deleteVideosBatch(
    List<String> ids,
    List<String> paths,
  ) async {
    try {
      final String? result = await _channel.invokeMethod('deleteVideosBatch', {
        'ids': ids,
        'paths': paths,
      });
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> renameFolder(String path, String newName) async {
    try {
      final String? result = await _channel.invokeMethod('renameFolder', {
        'path': path,
        'newName': newName,
      });
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> deleteFolder(String path) async {
    try {
      final String? result = await _channel.invokeMethod('deleteFolder', {
        'path': path,
      });
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  FileOpResult _mapStringToResult(String? val) {
    switch (val) {
      case 'success':
        return FileOpResult.success;
      case 'permission_required':
        return FileOpResult.safPermissionRequired;
      case 'cancelled':
        return FileOpResult.cancelled;
      default:
        return FileOpResult.error;
    }
  }
}
