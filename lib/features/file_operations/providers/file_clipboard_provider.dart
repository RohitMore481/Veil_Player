import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../library/models/video_item.dart';

enum ClipboardOpType { copy, move }

class FileClipboardItem {
  final String id;
  final String path;
  final String title;
  final String sourceFolderName;

  const FileClipboardItem({
    required this.id,
    required this.path,
    required this.title,
    required this.sourceFolderName,
  });

  factory FileClipboardItem.fromVideo(VideoItem video, String folderName) {
    return FileClipboardItem(
      id: video.id,
      path: video.path,
      title: video.title,
      sourceFolderName: folderName,
    );
  }
}

class FileClipboardState {
  final List<FileClipboardItem> items;
  final ClipboardOpType opType;

  const FileClipboardState({
    this.items = const [],
    this.opType = ClipboardOpType.copy,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get count => items.length;
  bool get isMove => opType == ClipboardOpType.move;
  bool get isCopy => opType == ClipboardOpType.copy;

  Set<String> get sourceFolderNames => items.map((i) => i.sourceFolderName).toSet();
  List<String> get ids => items.map((i) => i.id).toList();
  List<String> get paths => items.map((i) => i.path).toList();
}

class FileClipboardNotifier extends StateNotifier<FileClipboardState> {
  FileClipboardNotifier() : super(const FileClipboardState());

  void copySingle(VideoItem video, String folderName) {
    state = FileClipboardState(
      items: [FileClipboardItem.fromVideo(video, folderName)],
      opType: ClipboardOpType.copy,
    );
  }

  void moveSingle(VideoItem video, String folderName) {
    state = FileClipboardState(
      items: [FileClipboardItem.fromVideo(video, folderName)],
      opType: ClipboardOpType.move,
    );
  }

  void copyBatch(List<VideoItem> videos, String folderName) {
    if (videos.isEmpty) return;
    state = FileClipboardState(
      items: videos.map((v) => FileClipboardItem.fromVideo(v, folderName)).toList(),
      opType: ClipboardOpType.copy,
    );
  }

  void moveBatch(List<VideoItem> videos, String folderName) {
    if (videos.isEmpty) return;
    state = FileClipboardState(
      items: videos.map((v) => FileClipboardItem.fromVideo(v, folderName)).toList(),
      opType: ClipboardOpType.move,
    );
  }

  void clear() {
    state = const FileClipboardState();
  }
}

final fileClipboardProvider =
    StateNotifierProvider<FileClipboardNotifier, FileClipboardState>((ref) {
  return FileClipboardNotifier();
});
