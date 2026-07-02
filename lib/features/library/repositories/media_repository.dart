import '../models/video_item.dart';
import '../services/media_service.dart';
import '../../file_operations/services/file_operation_service.dart';
import '../../file_operations/services/permission_service.dart';
import '../../file_operations/services/media_store_service.dart';

class MediaRepository {
  final MediaService _mediaService;
  final FileOperationService _fileOperationService;
  final PermissionService _permissionService;
  final MediaStoreService _mediaStoreService;

  MediaRepository(
    this._mediaService,
    this._fileOperationService,
    this._permissionService,
    this._mediaStoreService,
  );

  Future<String> checkPermission() => _mediaService.checkPermission();

  Future<String> requestPermission() => _mediaService.requestPermission();

  Future<bool> openSettings() => _mediaService.openSettings();

  Future<List<VideoItem>> getVideos({
    required int limit,
    required int offset,
    String? folderName,
    String? folderPath,
  }) async {
    final rawList = await _mediaService.getVideos(
      limit: limit,
      offset: offset,
      folderName: folderName,
      folderPath: folderPath,
    );
    return rawList.map((map) => VideoItem.fromMap(map)).toList();
  }

  Future<List<FolderItem>> getFolders() async {
    final rawList = await _mediaService.getFolders();
    return rawList.map((map) => FolderItem.fromMap(map)).toList();
  }

  Future<String?> getThumbnail(String id, String path) =>
      _mediaService.generateThumbnail(id, path);

  Future<bool> savePlaybackPosition({
    required String id,
    required int positionMs,
    required int durationMs,
    required String title,
    required String path,
  }) => _mediaService.savePlaybackPosition(
    id: id,
    positionMs: positionMs,
    durationMs: durationMs,
    title: title,
    path: path,
  );

  Future<List<PlaybackHistoryItem>> getAllPlaybackPositions() async {
    final rawList = await _mediaService.getAllPlaybackPositions();
    return rawList.map((map) => PlaybackHistoryItem.fromMap(map)).toList();
  }

  Future<bool> clearPlaybackPosition(String id) =>
      _mediaService.clearPlaybackPosition(id);

  Future<double> getVolume() => _mediaService.getVolume();

  Future<bool> setVolume(double volume) => _mediaService.setVolume(volume);

  Future<double> getBrightness() => _mediaService.getBrightness();

  Future<bool> setBrightness(double brightness) =>
      _mediaService.setBrightness(brightness);

  Future<Map<dynamic, dynamic>?> getVideoMetadata(String path) =>
      _mediaStoreService.getVideoMetadata(path);

  Future<bool> savePlayerSetting(String key, dynamic value) =>
      _mediaService.savePlayerSetting(key, value);

  Future<dynamic> getPlayerSetting(String key, String type) =>
      _mediaService.getPlayerSetting(key, type);

  Future<Map<String, dynamic>> getAllPlayerSettings() =>
      _mediaService.getAllPlayerSettings();

  Future<bool> requestAudioFocus() => _mediaService.requestAudioFocus();

  Future<void> abandonAudioFocus() => _mediaService.abandonAudioFocus();

  Future<String?> pickSubtitleFile() async => _mediaService.pickSubtitleFile();

  Future<List<VideoItem>> searchVideos(String query) async {
    final rawList = await _mediaService.searchVideos(query);
    return rawList.map((map) => VideoItem.fromMap(map)).toList();
  }

  Future<bool> needsSystemConfirmationForWrite() =>
      _permissionService.needsSystemConfirmationForWrite();

  Future<bool> hasSafPermission(String path) =>
      _permissionService.hasSafPermission(path);

  Future<bool> requestSafPermission(String path) =>
      _permissionService.requestSafPermission(path);

  Future<bool> isStorageManager() => _permissionService.isStorageManager();

  Future<bool> requestManageStoragePermission() =>
      _permissionService.requestManageStoragePermission();

  Future<FileOpResult> renameVideo(String id, String path, String newName) =>
      _fileOperationService.renameVideo(id, path, newName);

  Future<FileOpResult> deleteVideo(String id, String path) =>
      _fileOperationService.deleteVideo(id, path);

  Future<FileOpResult> deleteVideosBatch(
    List<String> ids,
    List<String> paths,
  ) => _fileOperationService.deleteVideosBatch(ids, paths);

  Future<FileOpResult> renameFolder(String path, String newName) =>
      _fileOperationService.renameFolder(path, newName);

  Future<FileOpResult> deleteFolder(String path) =>
      _fileOperationService.deleteFolder(path);

  Future<bool> hideFolder(String path) => _mediaService.hideFolder(path);

  Future<bool> refreshFolder(String path) =>
      _mediaStoreService.refreshFolder(path);

  Future<bool> shareVideo(String path) => _mediaStoreService.shareVideo(path);

  Future<bool> clearThumbnailCache() => _mediaService.clearThumbnailCache();
}
