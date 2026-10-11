import 'audio_item.dart';

/// Wraps an [AudioTrackItem] with a unique [queueId] to guarantee stable
/// identity in the queue, even when identical tracks are queued multiple times.
class QueueItem {
  final String queueId;
  final AudioTrackItem track;

  const QueueItem({
    required this.queueId,
    required this.track,
  });

  Map<String, dynamic> toMap() => {
        'queueId': queueId,
        'track': track.toMap(),
      };

  factory QueueItem.fromMap(Map<dynamic, dynamic> map) {
    return QueueItem(
      queueId: map['queueId'] as String? ?? '',
      track: AudioTrackItem.fromMap(
        map['track'] as Map<dynamic, dynamic>? ?? {},
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          queueId == other.queueId;

  @override
  int get hashCode => queueId.hashCode;

  @override
  String toString() => 'QueueItem(queueId: $queueId, title: ${track.title})';
}
