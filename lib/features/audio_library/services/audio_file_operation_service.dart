import 'package:flutter/services.dart';
import '../../file_operations/services/file_operation_service.dart';

class AudioFileOperationService {
  static const _channel = MethodChannel('veil_player/media');

  Future<FileOpResult> renameAudio(String id, String path, String newName) async {
    try {
      final String? result = await _channel.invokeMethod(
        'renameAudio',
        {
          'id': id,
          'path': path,
          'newName': newName,
        },
      );
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> deleteAudio(String id, String path) async {
    try {
      final String? result = await _channel.invokeMethod(
        'deleteAudio',
        {
          'id': id,
          'path': path,
        },
      );
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> copyAudio(String path, String targetFolder) async {
    try {
      final String? result = await _channel.invokeMethod(
        'copyAudio',
        {
          'path': path,
          'targetFolder': targetFolder,
        },
      );
      return _mapStringToResult(result);
    } on PlatformException catch (_) {
      return FileOpResult.error;
    }
  }

  Future<FileOpResult> moveAudio(String id, String path, String targetFolder) async {
    try {
      final String? result = await _channel.invokeMethod(
        'moveAudio',
        {
          'id': id,
          'path': path,
          'targetFolder': targetFolder,
        },
      );
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
