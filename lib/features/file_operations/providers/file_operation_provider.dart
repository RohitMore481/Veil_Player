import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/permission_service.dart';
import '../services/media_store_service.dart';
import '../services/file_operation_service.dart';

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

final mediaStoreServiceProvider = Provider<MediaStoreService>((ref) {
  return MediaStoreService();
});

final fileOperationServiceProvider = Provider<FileOperationService>((ref) {
  return FileOperationService();
});
