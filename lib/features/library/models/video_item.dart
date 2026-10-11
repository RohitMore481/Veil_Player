class VideoItem {
  final String id;
  final String title;
  final String path;
  final Duration duration;
  final int size;
  final DateTime dateAdded;
  final String folderName;
  final String? thumbnailPath;
  final bool isWatched;

  const VideoItem({
    required this.id,
    required this.title,
    required this.path,
    required this.duration,
    required this.size,
    required this.dateAdded,
    required this.folderName,
    this.thumbnailPath,
    this.isWatched = true,
  });

  VideoItem copyWith({
    String? id,
    String? title,
    String? path,
    Duration? duration,
    int? size,
    DateTime? dateAdded,
    String? folderName,
    String? thumbnailPath,
    bool? isWatched,
  }) {
    return VideoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      dateAdded: dateAdded ?? this.dateAdded,
      folderName: folderName ?? this.folderName,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      isWatched: isWatched ?? this.isWatched,
    );
  }

  factory VideoItem.fromMap(Map<dynamic, dynamic> map) {
    return VideoItem(
      id: map['id'] as String,
      title: map['title'] as String,
      path: map['path'] as String,
      duration: Duration(milliseconds: (map['duration'] as num).toInt()),
      size: (map['size'] as num).toInt(),
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        (map['dateAdded'] as num).toInt() * 1000,
      ),
      folderName: map['folderName'] as String,
      thumbnailPath: map['thumbnailPath'] as String?,
      isWatched: map['isWatched'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'path': path,
      'duration': duration.inMilliseconds,
      'size': size,
      'dateAdded': dateAdded.millisecondsSinceEpoch ~/ 1000,
      'folderName': folderName,
      'thumbnailPath': thumbnailPath,
      'isWatched': isWatched,
    };
  }

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      final hrStr = hours.toString().padLeft(2, '0');
      return '$hrStr:$minStr:$secStr';
    }
    return '$minStr:$secStr';
  }

  String get formattedSize {
    if (size <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var doubleSize = size.toDouble();
    while (doubleSize >= 1024 && i < suffixes.length - 1) {
      doubleSize /= 1024;
      i++;
    }
    return '${doubleSize.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String get resolution {
    // MediaStore doesn't always guarantee width/height columns.
    // However, if we need standard representation, we can estimate from size, or let the player decode.
    // For local listing, we can display typical labels based on path, or keep it optional.
    return '';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path;

  @override
  int get hashCode => id.hashCode ^ path.hashCode;

  @override
  String toString() {
    return 'VideoItem(id: $id, title: $title, path: $path, duration: $duration)';
  }
}

class FolderItem {
  final String name;
  final String path;
  final int count;
  final int newVideosCount;
  final bool containsMovies;

  const FolderItem({
    required this.name,
    required this.path,
    required this.count,
    this.newVideosCount = 0,
    required this.containsMovies,
  });

    factory FolderItem.fromMap(Map<dynamic, dynamic> map) {
    return FolderItem(
      name: map['name'] as String,
      path: map['path'] as String? ?? '',
      count: (map['count'] as num).toInt(),
      newVideosCount: (map['newVideosCount'] as num?)?.toInt() ?? 0,
      containsMovies: map['containsMovies'] as bool? ?? false,
    );
  }

  /// Determines the single folder that best matches the last-watched video path.
  /// Guarantees at most ONE folder is ever returned, preventing multi-folder highlighting.
  static FolderItem? findLastWatchedFolder(
    List<FolderItem> folders,
    String? lastWatchedVideoPath,
  ) {
    if (lastWatchedVideoPath == null || lastWatchedVideoPath.isEmpty || folders.isEmpty) {
      return null;
    }

    final normVideoPath = lastWatchedVideoPath.replaceAll('\\', '/').toLowerCase();
    final lastSlash = normVideoPath.lastIndexOf('/');
    final directParentPath = lastSlash != -1 ? normVideoPath.substring(0, lastSlash) : '';

    // Priority 1: Exact match with the video's immediate parent directory
    if (directParentPath.isNotEmpty) {
      for (final folder in folders) {
        final normFolder = folder.path.replaceAll('\\', '/').toLowerCase();
        if (normFolder == directParentPath) {
          return folder;
        }
      }
    }

    // Priority 2: Deepest (longest path) matching ancestor directory
    FolderItem? bestAncestorMatch;
    int bestMatchLength = -1;

    for (final folder in folders) {
      final normFolder = folder.path.replaceAll('\\', '/').toLowerCase();
      if (normFolder.isNotEmpty && normVideoPath.startsWith('$normFolder/')) {
        if (normFolder.length > bestMatchLength) {
          bestMatchLength = normFolder.length;
          bestAncestorMatch = folder;
        }
      }
    }

    return bestAncestorMatch;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FolderItem &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}

class PlaybackHistoryItem {
  final String id;
  final String title;
  final String path;
  final int positionMs;
  final int durationMs;
  final int timestamp;

  const PlaybackHistoryItem({
    required this.id,
    required this.title,
    required this.path,
    required this.positionMs,
    required this.durationMs,
    required this.timestamp,
  });

  factory PlaybackHistoryItem.fromMap(Map<dynamic, dynamic> map) {
    return PlaybackHistoryItem(
      id: map['id'] as String,
      title: map['title'] as String,
      path: map['path'] as String,
      positionMs: (map['position'] as num).toInt(),
      durationMs: (map['duration'] as num).toInt(),
      timestamp: (map['timestamp'] as num).toInt(),
    );
  }

  double get progress => durationMs > 0 ? positionMs / durationMs : 0.0;
  
  String get remainingTime {
    final remainingMs = durationMs - positionMs;
    if (remainingMs <= 0) return 'Finished';
    final remaining = Duration(milliseconds: remainingMs);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m remaining';
    }
    return '${minutes}m remaining';
  }
}
