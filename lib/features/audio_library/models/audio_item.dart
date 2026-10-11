class AudioTrackItem {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumId;
  final String? albumArtUri;
  final String path;
  final String? contentUri;
  final Duration duration;
  final int size;
  final DateTime dateAdded;
  final int? trackNumber;
  final String folderName;
  final String folderPath;

  const AudioTrackItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.albumId,
    this.albumArtUri,
    required this.path,
    this.contentUri,
    required this.duration,
    required this.size,
    required this.dateAdded,
    this.trackNumber,
    required this.folderName,
    required this.folderPath,
  });

  AudioTrackItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumId,
    String? albumArtUri,
    String? path,
    String? contentUri,
    Duration? duration,
    int? size,
    DateTime? dateAdded,
    int? trackNumber,
    String? folderName,
    String? folderPath,
  }) {
    return AudioTrackItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      albumArtUri: albumArtUri ?? this.albumArtUri,
      path: path ?? this.path,
      contentUri: contentUri ?? this.contentUri,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      dateAdded: dateAdded ?? this.dateAdded,
      trackNumber: trackNumber ?? this.trackNumber,
      folderName: folderName ?? this.folderName,
      folderPath: folderPath ?? this.folderPath,
    );
  }

  factory AudioTrackItem.fromMap(Map<dynamic, dynamic> map) {
    final rawPath = map['path'] as String? ?? '';
    final filenameFallback = rawPath.isNotEmpty
        ? rawPath.split(RegExp(r'[/\\]')).last.replaceFirst(RegExp(r'\.[^.]+$'), '')
        : 'Unknown Track';

    final rawTitle = map['title'] as String?;
    final title = (rawTitle == null || rawTitle.trim().isEmpty)
        ? (filenameFallback.isNotEmpty ? filenameFallback : 'Unknown Track')
        : rawTitle.trim();

    final rawArtist = map['artist'] as String?;
    final artist = (rawArtist == null ||
            rawArtist.trim().isEmpty ||
            rawArtist.trim().toLowerCase() == '<unknown>')
        ? 'Unknown Artist'
        : rawArtist.trim();

    final rawAlbum = map['album'] as String?;
    final album = (rawAlbum == null ||
            rawAlbum.trim().isEmpty ||
            rawAlbum.trim().toLowerCase() == '<unknown>')
        ? 'Unknown Album'
        : rawAlbum.trim();

    final rawDuration = map['duration'];
    final durationMs = rawDuration is num
        ? rawDuration.toInt()
        : (rawDuration is String ? int.tryParse(rawDuration) ?? 0 : 0);

    final rawSize = map['size'];
    final sizeBytes = rawSize is num
        ? rawSize.toInt()
        : (rawSize is String ? int.tryParse(rawSize) ?? 0 : 0);

    final rawDateAdded = map['dateAdded'];
    final dateAddedSec = rawDateAdded is num
        ? rawDateAdded.toInt()
        : (rawDateAdded is String ? int.tryParse(rawDateAdded) ?? 0 : 0);
    final dateAdded = dateAddedSec > 0
        ? DateTime.fromMillisecondsSinceEpoch(dateAddedSec * 1000)
        : DateTime.fromMillisecondsSinceEpoch(0);

    final rawFolder = map['folderName'] as String?;
    final folderName = (rawFolder == null || rawFolder.trim().isEmpty)
        ? 'Music'
        : rawFolder.trim();

    final folderPath = map['folderPath'] as String? ?? '';

    final rawTrack = map['trackNumber'];
    final trackVal = rawTrack is num
        ? rawTrack.toInt()
        : (rawTrack is String ? int.tryParse(rawTrack) : null);
    final trackNumber = (trackVal != null && trackVal > 0)
        ? (trackVal >= 1000 ? trackVal % 1000 : trackVal)
        : null;

    return AudioTrackItem(
      id: map['id']?.toString() ?? '',
      title: title,
      artist: artist,
      album: album,
      albumId: map['albumId']?.toString(),
      albumArtUri: map['albumArtUri'] as String?,
      path: rawPath,
      contentUri: map['contentUri'] as String?,
      duration: Duration(milliseconds: durationMs < 0 ? 0 : durationMs),
      size: sizeBytes < 0 ? 0 : sizeBytes,
      dateAdded: dateAdded,
      trackNumber: trackNumber,
      folderName: folderName,
      folderPath: folderPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'albumId': albumId,
      'albumArtUri': albumArtUri,
      'path': path,
      'contentUri': contentUri,
      'duration': duration.inMilliseconds,
      'size': size,
      'dateAdded': dateAdded.millisecondsSinceEpoch ~/ 1000,
      'trackNumber': trackNumber,
      'folderName': folderName,
      'folderPath': folderPath,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioTrackItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path;

  @override
  int get hashCode => id.hashCode ^ path.hashCode;

  @override
  String toString() {
    return 'AudioTrackItem(id: $id, title: $title, artist: $artist, album: $album, path: $path, duration: $duration)';
  }
}
