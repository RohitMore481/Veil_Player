enum DiagnosticCategory {
  app,
  lifecycle,
  player,
  decoder,
  audio,
  subtitle,
  mediaSession,
  audioFocus,
  pip,
  navigation,
  storage,
  system,
  error,
}

enum DiagnosticSeverity {
  info,
  warning,
  error,
  critical,
}

class DiagnosticEvent {
  final DateTime timestamp;
  final DiagnosticCategory category;
  final DiagnosticSeverity severity;
  final String event;
  final Map<String, dynamic>? metadata;
  final String? playbackSessionId;

  const DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.severity,
    required this.event,
    this.metadata,
    this.playbackSessionId,
  });

  String get categoryName => category.name.toUpperCase();
  String get severityName => severity.name.toUpperCase();

  String toFormattedString() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final sessionTag = playbackSessionId != null ? ' [$playbackSessionId]' : '';
    final metaTag = (metadata != null && metadata!.isNotEmpty) ? ' metadata=$metadata' : '';
    return '$timeStr [$categoryName] [$severityName]$sessionTag $event$metaTag';
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'category': category.name,
      'severity': severity.name,
      'event': event,
      'metadata': metadata,
      'playbackSessionId': playbackSessionId,
    };
  }

  factory DiagnosticEvent.fromJson(Map<String, dynamic> json) {
    return DiagnosticEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      category: DiagnosticCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => DiagnosticCategory.app,
      ),
      severity: DiagnosticSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => DiagnosticSeverity.info,
      ),
      event: json['event'] as String? ?? '',
      metadata: json['metadata'] as Map<String, dynamic>?,
      playbackSessionId: json['playbackSessionId'] as String?,
    );
  }
}
