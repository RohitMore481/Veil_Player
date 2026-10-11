import 'diagnostic_event.dart';
import 'diagnostic_sanitizer.dart';

enum ReportType {
  applicationCrash,
  playbackAnomaly,
  uiResponsivenessAnomaly,
  unexpectedSessionTermination,
  manualDiagnosticReport,
  error,
  testPlaybackAnomaly,
}

class DiagnosticReport {
  final String id;
  final ReportType type;
  final DateTime timestamp;
  final String appVersion;
  final String buildNumber;
  final String platform;
  final Map<String, String> deviceInfo;
  final Map<String, String> sessionInfo;
  final Map<String, String>? playbackInfo;
  final String? errorCategory;
  final String? exceptionMessage;
  final String? stackTrace;
  final List<DiagnosticEvent> recentEvents;
  final String? userDescription;
  final int occurrenceCount;

  DiagnosticReport({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.deviceInfo,
    required this.sessionInfo,
    this.playbackInfo,
    this.errorCategory,
    this.exceptionMessage,
    this.stackTrace,
    required this.recentEvents,
    this.userDescription,
    this.occurrenceCount = 1,
  });

  String get typeDisplayName {
    switch (type) {
      case ReportType.applicationCrash:
        return 'Application Crash';
      case ReportType.playbackAnomaly:
        return 'Playback Anomaly';
      case ReportType.uiResponsivenessAnomaly:
        return 'UI Responsiveness Anomaly';
      case ReportType.unexpectedSessionTermination:
        return 'Unexpected Session Termination';
      case ReportType.manualDiagnosticReport:
        return 'Manual Diagnostic Report';
      case ReportType.error:
        return 'Application Error';
      case ReportType.testPlaybackAnomaly:
        return 'Test Playback Anomaly';
    }
  }

  /// Formats the report into a clean, human-readable plain text document.
  String generateTextReport() {
    final buffer = StringBuffer();

    buffer.writeln('================================================');
    buffer.writeln('VEIL PLAYER DIAGNOSTIC REPORT');
    buffer.writeln('================================================');
    buffer.writeln();
    buffer.writeln('Report ID:');
    buffer.writeln(id);
    buffer.writeln();
    buffer.writeln('Report Type:');
    buffer.writeln(typeDisplayName);
    if (occurrenceCount > 1) {
      buffer.writeln('Repeated Occurrence Count: $occurrenceCount');
    }
    buffer.writeln();
    buffer.writeln('Generated:');
    buffer.writeln(_formatDate(timestamp));
    buffer.writeln();

    if (userDescription != null && userDescription!.trim().isNotEmpty) {
      buffer.writeln('-----------------------------------------------');
      buffer.writeln('USER NOTES');
      buffer.writeln('-----------------------------------------------');
      buffer.writeln(DiagnosticSanitizer.sanitize(userDescription!.trim()));
      buffer.writeln();
    }

    buffer.writeln('-----------------------------------------------');
    buffer.writeln('APPLICATION');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln('Veil Player Version: $appVersion');
    buffer.writeln('Build Number: $buildNumber');
    buffer.writeln('Platform: $platform');
    buffer.writeln();

    buffer.writeln('-----------------------------------------------');
    buffer.writeln('DEVICE');
    buffer.writeln('-----------------------------------------------');
    deviceInfo.forEach((k, v) {
      buffer.writeln('$k: ${DiagnosticSanitizer.sanitize(v)}');
    });
    buffer.writeln();

    buffer.writeln('-----------------------------------------------');
    buffer.writeln('SESSION');
    buffer.writeln('-----------------------------------------------');
    sessionInfo.forEach((k, v) {
      buffer.writeln('$k: ${DiagnosticSanitizer.sanitize(v)}');
    });
    buffer.writeln();

    if (playbackInfo != null && playbackInfo!.isNotEmpty) {
      buffer.writeln('-----------------------------------------------');
      buffer.writeln('PLAYBACK');
      buffer.writeln('-----------------------------------------------');
      playbackInfo!.forEach((k, v) {
        buffer.writeln('$k: ${DiagnosticSanitizer.sanitize(v)}');
      });
      buffer.writeln();
    }

    if (exceptionMessage != null || errorCategory != null) {
      buffer.writeln('-----------------------------------------------');
      buffer.writeln('ERROR DETAILS');
      buffer.writeln('-----------------------------------------------');
      if (errorCategory != null) {
        buffer.writeln('Category: $errorCategory');
      }
      if (exceptionMessage != null) {
        buffer.writeln('Exception:');
        buffer.writeln(DiagnosticSanitizer.sanitize(exceptionMessage!));
      }
      if (stackTrace != null && stackTrace!.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Stack Trace:');
        buffer.writeln(DiagnosticSanitizer.sanitizeStackTrace(stackTrace!));
      }
      buffer.writeln();
    }

    buffer.writeln('-----------------------------------------------');
    buffer.writeln('RECENT DIAGNOSTIC EVENTS');
    buffer.writeln('-----------------------------------------------');
    if (recentEvents.isEmpty) {
      buffer.writeln('No recent events recorded in buffer.');
    } else {
      for (final event in recentEvents) {
        buffer.writeln(DiagnosticSanitizer.sanitize(event.toFormattedString()));
      }
    }
    buffer.writeln();

    buffer.writeln('-----------------------------------------------');
    buffer.writeln('PRIVACY & SECURITY NOTICE');
    buffer.writeln('-----------------------------------------------');
    buffer.writeln('This report was generated locally by Veil Player.');
    buffer.writeln('Media contents, screenshots, and full personal media file paths');
    buffer.writeln('are intentionally excluded to protect your privacy.');
    buffer.writeln('Nothing was uploaded automatically.');
    buffer.writeln('================================================');

    return buffer.toString();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'appVersion': appVersion,
      'buildNumber': buildNumber,
      'platform': platform,
      'deviceInfo': deviceInfo,
      'sessionInfo': sessionInfo,
      'playbackInfo': playbackInfo,
      'errorCategory': errorCategory,
      'exceptionMessage': exceptionMessage,
      'stackTrace': stackTrace,
      'recentEvents': recentEvents.map((e) => e.toJson()).toList(),
      'userDescription': userDescription,
      'occurrenceCount': occurrenceCount,
    };
  }

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) {
    return DiagnosticReport(
      id: json['id'] as String,
      type: ReportType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ReportType.error,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      appVersion: json['appVersion'] as String? ?? '1.0.0',
      buildNumber: json['buildNumber'] as String? ?? '1',
      platform: json['platform'] as String? ?? 'Android',
      deviceInfo: Map<String, String>.from(json['deviceInfo'] as Map? ?? {}),
      sessionInfo: Map<String, String>.from(json['sessionInfo'] as Map? ?? {}),
      playbackInfo: json['playbackInfo'] != null
          ? Map<String, String>.from(json['playbackInfo'] as Map)
          : null,
      errorCategory: json['errorCategory'] as String?,
      exceptionMessage: json['exceptionMessage'] as String?,
      stackTrace: json['stackTrace'] as String?,
      recentEvents: (json['recentEvents'] as List? ?? [])
          .map((e) => DiagnosticEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      userDescription: json['userDescription'] as String?,
      occurrenceCount: (json['occurrenceCount'] as num?)?.toInt() ?? 1,
    );
  }

  static String _formatDate(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }
}
