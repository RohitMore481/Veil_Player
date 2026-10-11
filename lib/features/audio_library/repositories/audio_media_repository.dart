import '../models/audio_item.dart';
import '../models/audio_folder_item.dart';
import '../services/audio_media_service.dart';

class AudioMediaRepository {
  final AudioMediaService _audioMediaService;

  AudioMediaRepository(this._audioMediaService);

  Future<String> checkAudioPermission() => _audioMediaService.checkAudioPermission();

  Future<String> requestAudioPermission() => _audioMediaService.requestAudioPermission();

  Future<bool> openSettings() => _audioMediaService.openSettings();

  Future<List<AudioTrackItem>> getAudioTracks({
    required int limit,
    required int offset,
    String? folderName,
    String? folderPath,
  }) async {
    final rawList = await _audioMediaService.getAudioTracks(
      limit: limit,
      offset: offset,
      folderName: folderName,
      folderPath: folderPath,
    );
    return rawList.map((map) => AudioTrackItem.fromMap(map)).toList();
  }

  Future<List<AudioFolderItem>> getAudioFolders() async {
    final rawList = await _audioMediaService.getAudioFolders();
    return rawList.map((map) => AudioFolderItem.fromMap(map)).toList();
  }
}
