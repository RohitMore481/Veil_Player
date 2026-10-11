import 'audio_item.dart';

class Playlist {
  final String id;
  final String name;
  final List<AudioTrackItem> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Playlist({
    required this.id,
    required this.name,
    this.tracks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get trackCount => tracks.length;

  Duration get totalDuration {
    var totalMs = 0;
    for (final t in tracks) {
      totalMs += t.duration.inMilliseconds;
    }
    return Duration(milliseconds: totalMs);
  }

  String get formattedTotalDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get formattedTrackCount {
    if (tracks.length == 1) return '1 song';
    return '${tracks.length} songs';
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<AudioTrackItem>? tracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'tracks': tracks.map((t) => t.toMap()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toJson() => toMap();

  factory Playlist.fromMap(Map<dynamic, dynamic> map) {
    final rawTracks = map['tracks'] as List<dynamic>? ?? [];
    final List<AudioTrackItem> trackList = [];
    for (final rt in rawTracks) {
      if (rt is Map) {
        trackList.add(AudioTrackItem.fromMap(rt));
      }
    }
    return Playlist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled Playlist',
      tracks: trackList,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  factory Playlist.fromJson(Map<dynamic, dynamic> json) => Playlist.fromMap(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Playlist &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
