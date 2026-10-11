class AudioFolderItem {
  final String name;
  final String path;
  final int trackCount;
  final Duration totalDuration;
  final int totalSize;

  const AudioFolderItem({
    required this.name,
    required this.path,
    required this.trackCount,
    this.totalDuration = Duration.zero,
    this.totalSize = 0,
  });

  factory AudioFolderItem.fromMap(Map<dynamic, dynamic> map) {
    final rawDuration = map['totalDuration'];
    final durationMs = rawDuration is num
        ? rawDuration.toInt()
        : (rawDuration is String ? int.tryParse(rawDuration) ?? 0 : 0);

    final rawSize = map['totalSize'];
    final size = rawSize is num
        ? rawSize.toInt()
        : (rawSize is String ? int.tryParse(rawSize) ?? 0 : 0);

    final rawCount = map['count'] ?? map['trackCount'];
    final count = rawCount is num
        ? rawCount.toInt()
        : (rawCount is String ? int.tryParse(rawCount) ?? 0 : 0);

    return AudioFolderItem(
      name: map['name'] as String? ?? 'Music',
      path: map['path'] as String? ?? '',
      trackCount: count < 0 ? 0 : count,
      totalDuration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      totalSize: size < 0 ? 0 : size,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'count': trackCount,
      'totalDuration': totalDuration.inMilliseconds,
      'totalSize': totalSize,
    };
  }

  String get formattedTrackCount {
    if (trackCount == 1) return '1 song';
    return '$trackCount songs';
  }

  String get formattedTotalDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get formattedTotalSize {
    if (totalSize <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var doubleSize = totalSize.toDouble();
    while (doubleSize >= 1024 && i < suffixes.length - 1) {
      doubleSize /= 1024;
      i++;
    }
    return '${doubleSize.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioFolderItem &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() {
    return 'AudioFolderItem(name: $name, path: $path, trackCount: $trackCount)';
  }
}
